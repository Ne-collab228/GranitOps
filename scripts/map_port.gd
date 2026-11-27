class_name MapPort
extends Level
## Карта 4: приморский город и порт «Северная гавань» (1,24 x 1,24 км, север = −Z, восток = +X).
##
## Море — вся южная граница. На берегу: контейнерный терминал с портальными кранами (восток), торговая гавань с
## пирсами, складами и диспетчерской (запад), пляж и набережная (юго-запад), городские кварталы (центр), промзона с
## железнодорожной веткой (северо-восток), нефтебаза (запад), мыс с маяком и радиомаяком (юго-восток), виллы на холмах
## и стадион (север) — точка эвакуации.
## Игрок в воду не попадает: вдоль воды, набережных и пирсов стоит невидимая стена (слой забора).
## Оптимизация: районы — по одному Geo с узкой палитрой, дальние — по visibility_range; вода — один меш с лёгким шейдером;
## контейнеры — коробки с одной коллизией на ряд.

const WATER_Y := 0.0
const APRON_H := 2.2
## Южный край асфальта и набережная (полоса 4,6 м шире).
const QZ := 376.0
const QZ_FRONT := 380.6
const QUAY_X0 := -262.0
const QUAY_X1 := 342.0
const SPAWN := Vector2(-545.0, 285.0)
const LIGHT := Vector2(482.0, 428.0)
const OIL := Vector2(-440.0, -40.0)
const STADIUM := Vector2(90.0, -300.0)
const HARBOR_HQ := Vector2(-135.0, 250.0)
## Пирсы: центр по x, южный конец по z, ширина.
const PIERS := [[-200.0, 520.0, 24.0], [-105.0, 520.0, 24.0], [-10.0, 500.0, 24.0]]
const CRANE_OBJ_X := 200.0

## Размеры зданий по улице (ширина вдоль, глубина) — для рядов вдоль дороги.
const BW := {"house": 10.4, "house_fence": 11.0, "house_east": 10.4, "house2": 11.0, "block": 17.0, "shop": 10.0, "cafe": 10.0,
	"garages": 14.0, "shed": 4.4, "booth": 3.0, "hq": 19.0, "ruin": 11.0, "warehouse": 18.0}
const BD := {"house": 7.6, "house_fence": 8.0, "house_east": 7.6, "house2": 9.0, "block": 10.0, "shop": 8.6, "cafe": 8.6,
	"garages": 6.2, "shed": 3.4, "booth": 3.0, "hq": 10.6, "ruin": 8.6, "warehouse": 12.0}
## Гарнизоны по типам: [стрелков у окон, внутри, на крыше, у дверей].
const GARR := {"house_fence": [1, 0, 0, 0], "house": [1, 0, 0, 0], "house2": [2, 0, 1, 0], "ruin": [1, 0, 0, 0], "cafe": [2, 0, 0, 0],
	"shop": [1, 0, 0, 1], "block": [3, 0, 1, 0], "house_east": [1, 0, 0, 0], "garages": [1, 0, 0, 0], "warehouse": [2, 0, 0, 0],
	"hq": [3, 1, 1, 1], "booth": [1, 0, 0, 0]}
const CONT_MATS := ["container", "container_blue", "container_green", "container_grey", "rust"]

var noise_c := FastNoiseLite.new()
var beacon_dish: Node3D
var beacon_alive := true
var beacon_node: MeshInstance3D
var beacon_lamp: MeshInstance3D
var crane_node: MeshInstance3D
var _gr := RandomNumberGenerator.new()
var _thin := RandomNumberGenerator.new()
var post_keep := 0.15
var garrison_keep := 0.025
var bld_log: Array = []
var _n_posts := 0
var _in_garrison := false
## Занятые места под здания: Vector3(x, z, радиус).
var _placed: Array[Vector3] = []
## Прямоугольники асфальта: [x0, z0, x1, z1, мягкий край, сила] — слой «бетон» рельефа.
var _paved_rects: Array = [
	[-262.0, 196.0, 342.0, 378.0, 8.0, 1.0],
	[-310.0, -150.0, 140.0, 192.0, 30.0, 0.8],
	[165.0, -170.0, 545.0, 128.0, 30.0, 0.7],
	[-522.0, -112.0, -358.0, 32.0, 20.0, 0.75],
	[40.0, -336.0, 140.0, -264.0, 8.0, 0.9],
	[450.0, 405.0, 510.0, 455.0, 12.0, 0.5],
]


func _configure() -> void:
	map_key = "port"
	title = "Порт «Северная гавань»"
	size = 1320.0
	cell = 3.0
	chunk = 110
	lod_dist = 260.0
	play_half = 620.0
	outer_half = 2430.0
	outer_cell = 30.0
	map_seed = 20261128
	spawn_max_h = 60.0
	orbit_center = Vector3(0, 5, 60)
	orbit_radius = 260.0
	orbit_height = 90.0
	backdrop_color = Color(0.5, 0.52, 0.5)
	# навигация только над водой не печётся: дно моря (−7 м) ниже нижней границы
	nav_aabb = AABB(Vector3(-620, -1.5, -620), Vector3(1240, 135, 1240))
	tree_mix = {"broadleaf": 0.4, "searsia": 0.4, "fir": 0.08, "dead": 0.12}
	grove_share = 0.35
	tree_density = 0.75
	veg_cell_grass = 36.0
	veg_cell_tree = 70.0
	site_points = [Vector3(SPAWN.x, SPAWN.y, 0), Vector3(OIL.x, OIL.y, 105), Vector3(STADIUM.x, STADIUM.y, 62), Vector3(LIGHT.x, LIGHT.y, 50),
		Vector3(-190, 20, 140), Vector3(0, 20, 140), Vector3(-90, 150, 90), Vector3(260, 40, 110), Vector3(400, 40, 110), Vector3(260, -90, 90), Vector3(420, -90, 90)]
	for k in 7:
		site_points.append(Vector3(-210.0 + k * 100.0, 286.0, 95))
	site_points.append(Vector3(-150, -60, 80))
	site_points.append(Vector3(30, -60, 80))


func _setup_noise() -> void:
	noise_a.seed = 77
	noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_a.frequency = 0.0062
	noise_a.fractal_octaves = 3
	noise_b.seed = 79
	noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_b.frequency = 0.03
	noise_b.fractal_octaves = 2
	noise_c.seed = 83
	noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_c.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_c.frequency = 0.0028
	noise_c.fractal_octaves = 4


func _terrain_tex() -> Dictionary:
	# сухая прибрежная земля, бетон (асфальт городских участков и порта), скала
	return {"a": "aerial_grass_rock", "b": "concrete_floor_worn_001", "r": "rock_boulder_dry", "tint": Vector3(0.95, 0.95, 0.9),
		"grass": Vector3(0.33, 0.37, 0.18), "grass_amt": 0.6}


## Южное море: светлое небо, тёплое солнце, голубоватая дымка.
func _tune_environment() -> void:
	env.tonemap_exposure = 1.02
	env.adjustment_contrast = 1.17
	env.adjustment_saturation = 1.12
	env.ambient_light_color = Color(0.6, 0.68, 0.8)
	env.ambient_light_sky_contribution = 0.58
	env.ambient_light_energy = 0.92
	env.fog_light_color = Color(0.68, 0.78, 0.88)
	env.fog_density = 0.0007
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.25
	sun.light_color = Color(1.0, 0.91, 0.76)
	sun.light_energy = 1.4


# ------------------------------------------------------------------ рельеф и береговая линия
## Z берега при данном x (где кончается суша). У портовой части — ровная линия набережной.
func _coast_z(x: float) -> float:
	var nat := 362.0 + 12.0 * sin(x / 70.0 + 1.0) - 40.0 * exp(-pow((x + 450.0) / 120.0, 2.0)) + 80.0 * exp(-pow((x - 480.0) / 65.0, 2.0))
	var w := smoothstep(-310.0, -262.0, x) * (1.0 - smoothstep(342.0, 395.0, x))
	return lerpf(nat, QZ_FRONT, w)


## Ширина полосы мелководья/откоса: на западе пляж, на востоке крутой берег.
func _shore_w(x: float) -> float:
	return lerpf(70.0, 12.0, smoothstep(-380.0, -290.0, x))


func _land_h(x: float, z: float) -> float:
	var near_coast := smoothstep(120.0, 330.0, z)
	var h := 2.6 + 0.006 * (QZ - z) + noise_a.get_noise_2d(x, z) * lerpf(1.3, 0.45, near_coast)
	h += noise_b.get_noise_2d(x, z) * 0.35
	# холмы на севере и по бокам
	var hills := smoothstep(-250.0, -560.0, z)
	h += hills * (30.0 + 26.0 * noise_c.get_noise_2d(x, z) + 8.0 * noise_a.get_noise_2d(x * 2.0, z * 2.0))
	var e := smoothstep(470.0, 640.0, absf(x))
	h += e * e * (34.0 + 18.0 * noise_c.get_noise_2d(x * 0.8, z * 0.8))
	# мыс маяка
	h += 15.0 * exp(-(pow(x - LIGHT.x, 2.0) + pow(z - LIGHT.y + 6.0, 2.0)) / (2.0 * 46.0 * 46.0))
	# за границей игровой зоны — горы
	var far := maxf(maxf(absf(x) - 600.0, -z - 600.0), 0.0)
	if far > 0.0:
		var ridge := 1.0 - absf(noise_a.get_noise_2d(x * 0.3 + 700.0, z * 0.3))
		h += far * 0.1 + ridge * ridge * minf(far, 1100.0) * 0.3
	return h


func base_height(x: float, z: float) -> float:
	var h := _land_h(x, z)
	var zc := _coast_z(x)
	var sw := _shore_w(x)
	# пляж: перед водой суша плавно опускается до 1,4 м
	var beach := 1.0 - smoothstep(-380.0, -290.0, x)
	if beach > 0.0 and z < zc + sw:
		var k := (1.0 - smoothstep(0.0, 45.0, zc - z)) * beach
		h = lerpf(h, 1.4, clampf(k, 0.0, 1.0))
	if z > zc:
		var t := clampf((z - zc) / sw, 0.0, 1.0)
		h = lerpf(h, -7.0, smoothstep(0.0, 1.0, t))
	return h


func _paved(x: float, z: float) -> float:
	var best := 0.0
	for r in _paved_rects:
		var cx := (float(r[0]) + float(r[2])) * 0.5
		var cz := (float(r[1]) + float(r[3])) * 0.5
		var dx := maxf(absf(x - cx) - (float(r[2]) - float(r[0])) * 0.5, 0.0)
		var dz := maxf(absf(z - cz) - (float(r[3]) - float(r[1])) * 0.5, 0.0)
		var d := sqrt(dx * dx + dz * dz)
		best = maxf(best, float(r[5]) * (1.0 - smoothstep(0.0, float(r[4]), d)))
	return best


## Цвет вершины: r — бетон/асфальт (застроенные участки и дороги), g — скала, b — дорога.
func _vertex_color(x: float, z: float, nrm: Vector3, rd: float) -> Color:
	var zc := _coast_z(x)
	var rock := maxf(smoothstep(0.84, 0.64, nrm.y), smoothstep(380.0, 420.0, x) * (1.0 - smoothstep(0.0, 26.0, absf(z - zc))) * 0.75)
	var road := 1.0 - smoothstep(2.2, 5.0, rd)
	return Color(maxf(_paved(x, z), road * 0.9), rock, road, 0.0)


func _setup_pads() -> void:
	roads = [
		# 0: набережный проспект
		PackedVector2Array([Vector2(-610, 262), Vector2(-500, 245), Vector2(-380, 215), Vector2(-270, 196), Vector2(-120, 190), Vector2(40, 190),
			Vector2(200, 190), Vector2(340, 188), Vector2(470, 170), Vector2(610, 120)]),
		# 1: Центральная — через порт и город к стадиону
		PackedVector2Array([Vector2(-80, 372), Vector2(-80, 270), Vector2(-80, 190), Vector2(-80, 60), Vector2(-80, -60), Vector2(-80, -170),
			Vector2(-30, -260), Vector2(70, -300)]),
		# 2: бульвар запад — восток, дальше в промзону
		PackedVector2Array([Vector2(-330, 20), Vector2(-80, 20), Vector2(130, 20), Vector2(165, 3), Vector2(330, 0), Vector2(540, 0), Vector2(610, -12)]),
		# 3: к нефтебазе
		PackedVector2Array([Vector2(-270, 196), Vector2(-340, 120), Vector2(-410, 60), Vector2(-430, 45)]),
		# 4: главный проезд контейнерного терминала
		PackedVector2Array([Vector2(180, 190), Vector2(180, 284), Vector2(180, 372)]),
		# 5: к пирсу торговой гавани
		PackedVector2Array([Vector2(-200, 190), Vector2(-200, 280), Vector2(-200, 372)]),
		# 6: к маяку
		PackedVector2Array([Vector2(335, 330), Vector2(395, 358), Vector2(445, 395), Vector2(478, 420)]),
		# 7: железная дорога (в промзону и терминал)
		PackedVector2Array([Vector2(610, 135), Vector2(480, 128), Vector2(360, 132), Vector2(285, 150), Vector2(262, 196), Vector2(262, 300)]),
		# 8: к виллам на северо-востоке
		PackedVector2Array([Vector2(165, 3), Vector2(220, -90), Vector2(260, -190), Vector2(240, -290), Vector2(170, -325), Vector2(100, -312)]),
		# 9: к виллам на северо-западе
		PackedVector2Array([Vector2(-80, -60), Vector2(-160, -110), Vector2(-220, -190), Vector2(-230, -290), Vector2(-170, -360), Vector2(-60, -350)]),
	]
	pads = [
		{"c": Vector2(40, 286), "half": Vector2(300, 90), "m": 10.0, "h": APRON_H},
		{"c": STADIUM, "half": Vector2(50, 36), "m": 14.0, "h": base_height(STADIUM.x, STADIUM.y)},
		{"c": OIL, "half": Vector2(82, 72), "m": 24.0, "h": base_height(OIL.x, OIL.y)},
		{"c": SPAWN, "half": Vector2(6, 6), "m": 12.0, "h": base_height(SPAWN.x, SPAWN.y)},
		{"c": LIGHT, "half": Vector2(22, 20), "m": 18.0, "h": base_height(LIGHT.x, LIGHT.y)},
	]


## Деревья и камни: не в воде, не на пляже у самой воды, не в застройке.
func _free_spot(x: float, z: float, margin := 2.0) -> bool:
	if not super._free_spot(x, z, margin):
		return false
	if ground(x, z) < 1.3 or _paved(x, z) > 0.3:
		return false
	if margin >= 2.4:
		for sp in site_points:
			if absf(x - sp.x) < sp.z * 0.8 and absf(z - sp.y) < sp.z * 0.8:
				return false
	return true


# ------------------------------------------------------------------ вода
const WATER_SHADER := "shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform vec3 deep_col : source_color = vec3(0.004, 0.05, 0.1);
uniform vec3 shallow_col : source_color = vec3(0.03, 0.2, 0.25);
uniform float amp = 1.0;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 wave(vec2 p, vec2 d, float k, float s, float a, float t) {
	float ph = dot(d, p) * k + t * s;
	return d * (k * a * cos(ph));
}

void fragment() {
	vec2 p = wp.xz;
	float t = TIME;
	vec2 g = wave(p, normalize(vec2(1.0, 0.35)), 0.23, 1.1, 0.12, t);
	g += wave(p, normalize(vec2(-0.4, 1.0)), 0.41, 1.5, 0.07, t);
	g += wave(p, normalize(vec2(0.7, -0.8)), 0.83, 2.1, 0.035, t);
	g += wave(p, normalize(vec2(-1.0, -0.2)), 1.7, 2.9, 0.016, t);
	float dist = length(VERTEX);
	g *= amp * (1.0 - smoothstep(80.0, 420.0, dist) * 0.8);
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float depth = COLOR.r;
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, depth));
	float foam = COLOR.g * (0.5 + 0.5 * sin(p.x * 0.8 + p.y * 0.65 + t * 1.7)) * (0.6 + 0.4 * sin(p.y * 1.7 - t * 1.1));
	foam = clamp(foam, 0.0, 1.0);
	ALBEDO = mix(col, vec3(0.92, 0.95, 0.95), foam * 0.75);
	ALPHA = clamp(mix(0.55, 0.97, depth) + foam * 0.4, 0.0, 1.0);
	ROUGHNESS = 0.2;
	SPECULAR = 0.14;
	METALLIC = 0.0;
}
"


## Один меш: сетка 12 м над мелководьем и крупные квадраты до горизонта. Цвет вершины: r — глубина, g — пена у берега.
func _build_water() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cs := 12.0
	var x0 := -648.0
	var x1 := 648.0
	var z0 := 280.0
	var z1 := 648.0
	var nx := int(round((x1 - x0) / cs))
	var nz := int(round((z1 - z0) / cs))
	for iz in nz:
		for ix in nx:
			var xa := x0 + ix * cs
			var za := z0 + iz * cs
			var gs := [ground(xa, za), ground(xa + cs, za), ground(xa + cs, za + cs), ground(xa, za + cs)]
			if minf(minf(gs[0], gs[1]), minf(gs[2], gs[3])) > 1.2:
				continue
			var vs := [Vector3(xa, WATER_Y, za), Vector3(xa + cs, WATER_Y, za), Vector3(xa + cs, WATER_Y, za + cs), Vector3(xa, WATER_Y, za + cs)]
			for k in [0, 2, 1, 0, 3, 2]:
				var gh: float = gs[k]
				st.set_color(Color(clampf(-gh / 5.0, 0.0, 1.0), clampf(1.0 - absf(gh + 0.1) / 0.9, 0.0, 1.0), 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(vs[k])
	var big := 6000.0
	# вокруг сетки — глубокая вода (над сушей она скрыта рельефом)
	for q in [[-big, -big, big, z0], [-big, z0, x0, big], [x1, z0, big, big], [x0, z1, x1, big]]:
		var qa: Array = q
		var vs2 := [Vector3(qa[0], WATER_Y, qa[1]), Vector3(qa[2], WATER_Y, qa[1]), Vector3(qa[2], WATER_Y, qa[3]), Vector3(qa[0], WATER_Y, qa[3])]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(Color(1, 0, 0))
			st.set_normal(Vector3.UP)
			st.add_vertex(vs2[k])
	var mi := MeshInstance3D.new()
	mi.name = "water"
	mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	add_child(mi)


## Z воды вдоль x: первая точка, где рельеф уходит под воду; на набережной — край плиты.
func _shore_front(x: float) -> float:
	if x >= QUAY_X0 and x <= QUAY_X1:
		return QZ_FRONT - 0.4
	var cx := clampf(x, -650.0, 650.0)
	var z := 150.0
	while z < 700.0:
		if ground(cx, z) < -0.2:
			return z
		z += 1.5
	return 700.0


## Невидимая стена вдоль воды, набережных и по бортам пирсов: в воду не попасть ни пешком, ни на машине.
func _build_shore_fence() -> void:
	var step := 12.0
	var pts: Array[Vector2] = []
	var x := -play_half - 24.0
	while x <= play_half + 24.0:
		pts.append(Vector2(x, _shore_front(x)))
		x += step
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var skip := false
		for p in PIERS:
			var px0: float = float(p[0]) - float(p[2]) * 0.5 - 0.3
			var px1: float = float(p[0]) + float(p[2]) * 0.5 + 0.3
			if maxf(a.x, b.x) > px0 and minf(a.x, b.x) < px1:
				skip = true
		if skip:
			continue
		_fence_wall(a, b)
	for p in PIERS:
		var cx: float = p[0]
		var ze: float = p[1]
		var hw: float = float(p[2]) * 0.5
		_fence_wall(Vector2(cx - hw, QZ_FRONT - 0.4), Vector2(cx - hw, ze))
		_fence_wall(Vector2(cx + hw, QZ_FRONT - 0.4), Vector2(cx + hw, ze))
		_fence_wall(Vector2(cx - hw, ze), Vector2(cx + hw, ze))


func _fence_wall(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.1:
		return
	var s := BoxShape3D.new()
	s.size = Vector3(l + 0.4, 9.0, 0.5)
	_fence_shapes.append([s, Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3((a.x + b.x) * 0.5, 0.5, (a.y + b.y) * 0.5))])


# ------------------------------------------------------------------ помощники построек
func _set_palette(on: bool) -> void:
	if on:
		Bld.walls_house = ["plaster_tan", "stucco_yellow"]
		Bld.walls_block = ["concrete", "plaster_tan"]
		Bld.roofs = ["roof_red"]
	else:
		Bld.walls_house = ["plaster_tan", "stucco_blue", "stucco_yellow", "concrete"]
		Bld.walls_block = ["concrete", "plaster_tan", "stucco_yellow"]
		Bld.roofs = ["slate", "roof_red", "iron"]


func _far(mi: MeshInstance3D, d: float) -> void:
	mi.visibility_range_end = d
	mi.visibility_range_end_margin = 20.0
	veg_ranges.append([mi, d])


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


func _garrison(out: Dictionary, info: Dictionary, fire_n: int, inside_n := 0, roof_n := 0, door_n := 0) -> void:
	if info.is_empty():
		return
	_in_garrison = true
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
	_in_garrison = false


func _e_face(p: Vector3, dir: Vector3, kind: int, hold: bool) -> void:
	_e(p.x, p.z, rad_to_deg(atan2(-dir.x, -dir.z)), kind, [], p.y, hold)


## Одиночные посты (без маршрута, не снайперы) прореживаются: см. post_keep.
func _e(x: float, z: float, yaw_deg: float, kind := 0, route := [], y := -1000.0, hold := false) -> void:
	if route.is_empty() and kind != 2 and not _in_garrison and _thin.randf() > post_keep:
		return
	super._e(x, z, yaw_deg, kind, route, y, hold)


## Точка и направление на ломаной на расстоянии dist от начала: [Vector2, Vector2].
func _line_at(line: PackedVector2Array, dist: float) -> Array:
	var acc := 0.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var l := a.distance_to(b)
		if dist <= acc + l or i == line.size() - 2:
			var tt := clampf((dist - acc) / maxf(l, 0.001), 0.0, 1.0)
			return [a.lerp(b, tt), (b - a) / maxf(l, 0.001)]
		acc += l
	return [line[0], Vector2.RIGHT]


func _spot_free(p: Vector3) -> bool:
	for q in _placed:
		if Vector2(p.x, p.y).distance_to(Vector2(q.x, q.y)) < (p.z + q.z) * 0.86:
			return false
	return true


## Ряд зданий вдоль дороги (фасадом к ней). items: тип, [тип, opt] или число (пропуск, м); side +1 — справа по ходу линии.
## Здание пропускается, если угол упирается в другую дорогу, в воду или в уже построенное.
func _row(g: Geo, line: PackedVector2Array, t0: float, side: float, items: Array, gap := 4.5, setback := 3.0, garr := {}) -> void:
	var t := t0
	for it in items:
		if it is float or it is int:
			t += float(it)
			continue
		var kind: String = it if it is String else String(it[0])
		var opt: Dictionary = {} if it is String else it[1]
		var w: float = float(opt.get("w", BW.get(kind, 12.0)))
		var d: float = float(opt.get("d", BD.get(kind, 9.0)))
		var pd := _line_at(line, t + w * 0.5)
		var p: Vector2 = pd[0]
		var dir: Vector2 = pd[1]
		var n := Vector2(-dir.y, dir.x) * side
		var c := p + n * (road_half + setback + d * 0.5)
		var yaw := atan2(-n.x, -n.y)
		t += w + gap
		var along := dir
		var r := sqrt(w * w + d * d) * 0.5
		var ok := _spot_free(Vector3(c.x, c.y, r)) and ground(c.x, c.y) > 1.2
		if ok:
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					var q: Vector2 = c + along * (w * 0.5 * cx) + n * (d * 0.5 * cz)
					if road_dist(q.x, q.y) < 3.8 or ground(q.x, q.y) < 1.0:
						ok = false
		if not ok:
			continue
		_placed.append(Vector3(c.x, c.y, r))
		_cover_spots.append(Vector3(c.x, c.y, r + 1.5))
		var out := {}
		var info := _bld(g, kind, c.x, c.y, yaw, opt, out)
		var gp: Array = garr.get(kind, GARR.get(kind, [0, 0, 0, 0]))
		_garrison(out, info, gp[0], gp[1], gp[2], gp[3])


# ------------------------------------------------------------------ постройки
func _build_sites() -> void:
	_n_posts = enemy_spawns.size()
	_set_palette(true)
	_build_water()
	_build_shore_fence()
	_build_spawn()
	_build_beach()
	await get_tree().process_frame
	_build_port_west()
	_build_piers_and_ships()
	await get_tree().process_frame
	_build_terminal()
	await get_tree().process_frame
	_build_city()
	await get_tree().process_frame
	_build_industry()
	_build_rail()
	await get_tree().process_frame
	_build_oil()
	_build_lighthouse()
	_build_villas()
	_build_stadium()
	_build_field_cover()
	_set_palette(false)
	print("ПОРТ: врагов %d (посты и патрули до построек %d), укрытий в поле %d, зданий %d" % [enemy_spawns.size(), _n_posts, field_cover_count, bld_log.size()])
	_define_vehicles()
	blast_fx["fuel"] = {"fires": [[Vector3(-8, 0.5, 0), 1.8], [Vector3(8, 0.5, 2), 1.6], [Vector3(0, 0.5, -10), 1.6], [Vector3(0, 0.5, 10), 1.4]],
		"blasts": [[0.4, Vector3(-9, 2, 0)], [0.9, Vector3(9, 2, -4)], [1.5, Vector3(0, 3, 12)], [2.2, Vector3(0, 3, -12)]]}
	blast_fx["crane"] = {"fires": [[Vector3(-3, 0.4, 0), 1.5], [Vector3(3, 0.4, -2), 1.3]], "blasts": [[0.5, Vector3(0, 2, 0)], [1.2, Vector3(0, 6, -4)]]}
	blast_fx["beacon"] = {"fires": [[Vector3(0, 0.4, 0), 1.6], [Vector3(1.5, 0.3, -1), 1.2]], "blasts": [[0.5, Vector3(0, 2, 0)], [1.2, Vector3(-1, 3, 1)]]}


func _build_spawn() -> void:
	var y: float = pads[3].h
	spawn_point = Vector3(SPAWN.x, y + 0.2, SPAWN.y)
	var g := Geo.new()
	_barrier(g, SPAWN.x + 9.0, SPAWN.y - 12.0, 0.3, ground(SPAWN.x + 9.0, SPAWN.y - 12.0) - 0.05)
	_sandbags(g, Vector2(SPAWN.x - 12.0, SPAWN.y - 20.0), Vector2(SPAWN.x - 7.0, SPAWN.y - 20.0), ground(SPAWN.x - 9.0, SPAWN.y - 20.0) - 0.1, 3)
	_ammo_crate(SPAWN.x + 4.0, SPAWN.y - 6.0, y, 0.4)
	_far(g.finish(self, "spawn"), 200.0)


## Пляж и набережная юго-запада: кафе вдоль проспекта, вышка спасателей, лодки на песке.
func _build_beach() -> void:
	var g := Geo.new()
	var saved := rng.state
	rng.seed = 9111
	_gr.seed = 9112
	var r0: PackedVector2Array = roads[0]
	# по ходу линии (на восток) справа — юг: кафе и домики у пляжа
	_row(g, r0, 30.0, 1.0, ["cafe", 14.0, "shop", 8.0, "shed", 10.0, "cafe", 16.0, "house2", 10.0, "cafe", 8.0, "shed"], 6.0, 4.0)
	_tower(g, -470.0, 305.0, false, ground(-470.0, 305.0) - 0.05)
	_tower(g, -380.0, 280.0, false, ground(-380.0, 280.0) - 0.05)
	for b in [[-455.0, 322.0, 0.2], [-430.0, 326.0, 0.5], [-505.0, 318.0, -0.3]]:
		_boat(g, b[0], b[1], b[2])
	for b2 in [[-520.0, 240.0, 0.3], [-415.0, 215.0, 1.4], [-330.0, 205.0, 0.2]]:
		_barrier(g, b2[0], b2[1], b2[2], ground(b2[0], b2[1]) - 0.05)
	_ammo_crate(-440.0, 270.0, ground(-440.0, 270.0), 0.3)
	_far(g.finish(self, "beach"), 300.0)
	rng.state = saved


func _boat(g: Geo, x: float, z: float, yaw: float) -> void:
	var y := ground(x, z) - 0.05
	var rot := Basis(Vector3.UP, yaw)
	g.box_xf("container_blue", Transform3D(rot, Vector3(x, y + 0.5, z)), Vector3(5.2, 1.0, 1.9), true)
	g.box_xf("plaster", Transform3D(rot, Vector3(x, y + 1.05, z) + rot * Vector3(1.3, 0, 0)), Vector3(1.4, 0.9, 1.5), false)
	g.box_xf("plate_dark", Transform3D(rot, Vector3(x, y + 1.0, z) + rot * Vector3(-0.6, 0, 0)), Vector3(3.4, 0.08, 1.6), false)
	cover_points.append(Vector3(x, y, z) + rot * Vector3(0, 0, 1.6))
	cover_points.append(Vector3(x, y, z) + rot * Vector3(0, 0, -1.6))


# ------------------------------------------------------------------ торговая гавань (запад набережной)
func _build_port_west() -> void:
	var g := Geo.new()
	var saved := rng.state
	rng.seed = 9211
	_gr.seed = 9212
	var y := APRON_H
	# диспетчерская с разведданными (второй этаж)
	var oh := {}
	var ih := _bld(g, "hq", HARBOR_HQ.x, HARBOR_HQ.y, 0.0, {}, oh)
	_garrison(oh, ih, 3, 1, 1, 1)
	var best := Vector3(HARBOR_HQ.x, y + 3.7, HARBOR_HQ.y - 2.0)
	for p in oh.get("inside", []):
		if (p as Vector3).y > best.y - 0.5:
			best = p
	g.box("wood_dark", Vector3(best.x, best.y + 0.4, best.z), Vector3(1.3, 0.8, 0.8), 0.0, true)
	_make_intel(Vector3(best.x, best.y + 0.84, best.z))
	# склады: два ряда
	for it in [[-232.0, 232.0, 20.0, 11.0], [-170.0, 232.0, 22.0, 12.0], [-55.0, 232.0, 24.0, 12.0], [-8.0, 232.0, 18.0, 11.0],
			[-240.0, 322.0, 22.0, 12.0], [-60.0, 318.0, 24.0, 12.0], [-20.0, 335.0, 16.0, 10.0]]:
		var o := {}
		_garrison(o, _bld(g, "warehouse", it[0], it[1], 0.0 if float(it[1]) < 300.0 else PI, {"w": it[2], "d": it[3]}, o), 2, 0, 0, 0)
	# КПП на въезде с Центральной
	var ob := {}
	_garrison(ob, _bld(g, "booth", -72.0, 205.0, PI * 0.5, {"boom": true}, ob), 1, 0, 0, 0)
	_bld(g, "shed", -150.0, 215.0, 0.0, {"iron": true})
	_bld(g, "shed", -105.0, 300.0, 0.0)
	# портальные краны над акваторией между пирсами
	_crane(g, -152.0, QZ_FRONT - 3.2, true)
	_crane(g, -57.0, QZ_FRONT - 3.2, true)
	# двор: контейнеры, поддоны, мешки, блоки
	for c in [[-140.0, 285.0, 0.0], [-128.0, 285.0, 0.0], [-134.0, 288.5, 0.0], [-100.0, 275.0, 1.57], [-30.0, 290.0, 0.1], [-30.0, 296.5, 0.0]]:
		_cstack(g, c[0], c[1], c[2], 1 + rng.randi() % 2)
	_wreck(g, -110.0, 262.0, 0.4)
	_wreck(g, -175.0, 270.0, 1.3)
	for b in [[-100.0, 220.0, 0.1], [-145.0, 268.0, 1.5], [-45.0, 270.0, 0.2], [-215.0, 262.0, 1.57], [-190.0, 340.0, 0.0]]:
		_barrier(g, b[0], b[1], b[2], y)
	for sb in [[-120.0, 222.0, -115.0, 222.0], [-85.0, 240.0, -85.0, 245.0], [-175.0, 300.0, -170.0, 300.0], [-35.0, 262.0, -30.0, 262.0]]:
		_sandbags(g, Vector2(sb[0], sb[1]), Vector2(sb[2], sb[3]), y, 4)
	for c2 in [[-155.0, 222.0, 1.2], [-92.0, 270.0, 1.3], [-91.0, 271.4, 1.0], [-66.0, 292.0, 1.2]]:
		_crate(g, c2[0], c2[1], c2[2], rng.randf_range(-0.4, 0.4), y)
	_barrels(-215.0, 298.0, 4, y)
	_barrels(-90.0, 346.0, 3, y)
	_ammo_crate(-110.0, 224.0, y, 0.3)
	_ammo_crate(-50.0, 300.0, y, 1.0)
	for k in 8:
		_lamp(g, -240.0 + k * 40.0, 214.0, y, 0.0)
	_quay_furniture(g, QUAY_X0 + 6.0, -6.0)
	_far(g.finish(self, "port_west"), 340.0)
	rng.state = saved


## Швартовые тумбы вдоль кромки набережной.
func _quay_furniture(g: Geo, x0: float, x1: float) -> void:
	var x := x0
	while x < x1:
		var skip := false
		for p in PIERS:
			if absf(x - float(p[0])) < float(p[2]) * 0.5 + 3.0:
				skip = true
		if not skip:
			g.cyl("plate_dark", Transform3D(Basis(), Vector3(x, APRON_H + 0.3, QZ_FRONT - 1.0)), 0.3, 0.6, 8, false)
		x += 20.0


# ------------------------------------------------------------------ пирсы и суда
func _build_piers_and_ships() -> void:
	var g := Geo.new()
	g.cast_shadows = false
	var saved := rng.state
	rng.seed = 9311
	_gr.seed = 9312
	var top := APRON_H + 0.02
	for p in PIERS:
		var cx: float = p[0]
		var ze: float = p[1]
		var w: float = p[2]
		var z0 := QZ_FRONT - 4.0
		g.box("floor", Vector3(cx, (top - 6.5) * 0.5, (z0 + ze) * 0.5), Vector3(w, top + 6.5, ze - z0), 0.0, true)
		# швартовые тумбы и фонари по краям, контейнеры и мешки на пирсе
		var zz := QZ_FRONT + 10.0
		while zz < ze - 6.0:
			for s in [-1.0, 1.0]:
				g.cyl("plate_dark", Transform3D(Basis(), Vector3(cx + s * (w * 0.5 - 1.0), top + 0.3, zz)), 0.3, 0.6, 8, false)
			zz += 20.0
		for s2 in [-1.0, 1.0]:
			_lamp(g, cx + s2 * (w * 0.5 - 1.6), QZ_FRONT + 40.0, top, 0.0 if s2 < 0.0 else PI)
	# контейнеры и склад на пирсах — укрытия
	_cstack(g, -200.0, 430.0, 0.0, 2)
	_cstack(g, -200.0, 452.0, 0.0, 1)
	_cstack(g, -105.0, 420.0, 1.57, 2)
	_cstack(g, -105.0, 470.0, 0.0, 1)
	_cstack(g, -10.0, 425.0, 0.0, 2)
	_sandbags(g, Vector2(-206.0, 405.0), Vector2(-200.0, 405.0), top, 4)
	_sandbags(g, Vector2(-111.0, 495.0), Vector2(-105.0, 495.0), top, 4)
	_crate(g, -10.0, 470.0, 1.2, 0.3, top)
	_ammo_crate(-198.0, 480.0, top, 0.5)
	# суда у пирсов: нос смотрит в море (+Z)
	_ship(g, Vector3(-182.0, WATER_Y, 442.0), 0.0, 96.0, 17.0, 0)
	_ship(g, Vector3(-124.0, WATER_Y, 452.0), 0.0, 84.0, 15.0, 1)
	_ship(g, Vector3(10.0, WATER_Y, 440.0), 0.0, 100.0, 18.0, 0)
	# сухогруз у набережной терминала: вдоль оси X
	_ship(g, Vector3(200.0, WATER_Y, QZ_FRONT + 17.0), PI * 0.5, 186.0, 30.0, 0)
	# буксир
	_ship(g, Vector3(-60.0, WATER_Y, 495.0), 0.0, 34.0, 9.0, 2)
	_far(g.finish(self, "piers"), 420.0)
	rng.state = saved


## Судно: центр с y = уровень воды, нос в +Z (локально), yaw. kind: 0 контейнеровоз, 1 танкер, 2 буксир.
func _ship(g: Geo, c: Vector3, yaw: float, length: float, beam: float, kind: int) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var top := 5.4 if kind != 2 else 2.8
	var hull_mat := "rust" if kind == 0 else ("plate_dark" if kind == 1 else "container_blue")
	var body_l := length * 0.78
	var z_mid := -length * 0.08
	g.box_xf(hull_mat, Transform3D(rot, c + rot * Vector3(0, (top - 3.0) * 0.5, z_mid)), Vector3(beam, top + 3.0, body_l), false)
	g.collider("metal", Transform3D(rot, c + rot * Vector3(0, (top - 3.0) * 0.5, z_mid)), Vector3(beam, top + 3.0, body_l))
	# нос: клин
	var zb := z_mid + body_l * 0.5
	var tip := length * 0.5
	var hb := beam * 0.5
	var hh := tip - zb
	var st := g._st(hull_mat)
	var yb := c.y - 3.0
	var yt := c.y + top
	var nr := (rot * Vector3(hh, 0, hb)).normalized()
	var nl := (rot * Vector3(-hh, 0, hb)).normalized()
	var a0 := c + rot * Vector3(hb, yb - c.y, zb)
	var a1 := c + rot * Vector3(hb, yt - c.y, zb)
	var b0 := c + rot * Vector3(-hb, yb - c.y, zb)
	var b1 := c + rot * Vector3(-hb, yt - c.y, zb)
	var t0 := c + rot * Vector3(0, yb - c.y, tip)
	var t1 := c + rot * Vector3(0, yt - c.y, tip)
	Geo.tri(st, a0, a1, t1, nr, 0.3)
	Geo.tri(st, a0, t1, t0, nr, 0.3)
	Geo.tri(st, b0, b1, t1, nl, 0.3)
	Geo.tri(st, b0, t1, t0, nl, 0.3)
	Geo.tri(g._st("plate_dark"), a1, b1, t1, Vector3.UP, 0.3)
	# палуба
	g.box_xf("plate_dark", Transform3D(rot, c + rot * Vector3(0, top + 0.08, z_mid)), Vector3(beam - 0.4, 0.16, body_l - 0.2), false)
	# надстройка на корме и труба
	var sz := z_mid - body_l * 0.5 + (4.0 if kind == 2 else 9.0)
	if kind == 2:
		g.box_xf("plaster", Transform3D(rot, c + rot * Vector3(0, top + 2.2, sz)), Vector3(beam * 0.7, 4.0, 8.0), false)
		g.cyl("plate_dark", Transform3D(rot, c + rot * Vector3(0, top + 5.2, sz - 1.0)), 0.8, 2.6, 8, false)
		return
	g.box_xf("plaster", Transform3D(rot, c + rot * Vector3(0, top + 6.0, sz)), Vector3(beam * 0.78, 12.0, 14.0), false)
	g.box_xf("plate_dark", Transform3D(rot, c + rot * Vector3(0, top + 12.4, sz + 1.0)), Vector3(beam * 0.9, 0.8, 9.0), false)
	g.box_xf("glass", Transform3D(rot, c + rot * Vector3(0, top + 13.3, sz + 1.0)), Vector3(beam * 0.85, 1.4, 8.4), false)
	g.cyl("rust", Transform3D(rot, c + rot * Vector3(0, top + 15.0, sz - 3.5)), 1.7, 5.0, 10, false)
	g.collider("metal", Transform3D(rot, c + rot * Vector3(0, top + 6.0, sz)), Vector3(beam * 0.78, 12.0, 14.0))
	# груз
	if kind == 0:
		var zs := sz + 10.0
		var zend := z_mid + body_l * 0.5 - 5.0
		var ncol := maxi(1, int((beam - 2.0) / 2.6))
		var zi := 0
		while zs + 6.1 < zend:
			var lv := 1 + (zi * 7 + 3) % 3
			for xi in ncol:
				var lx := (xi - (ncol - 1) * 0.5) * 2.55
				var lvl := lv if (xi + zi) % 4 != 0 else maxi(lv - 1, 1)
				for k in lvl:
					var mat: String = CONT_MATS[(xi * 3 + zi * 5 + k) % 5]
					g.box_xf(mat, Transform3D(rot, c + rot * Vector3(lx, top + 0.16 + 1.3 + k * 2.6, zs + 3.05)), Vector3(2.44, 2.6, 6.06), false)
			zs += 6.5
			zi += 1
	else:
		# танкер: трубопровод и горловины
		g.box_xf("rust", Transform3D(rot, c + rot * Vector3(0, top + 0.9, z_mid + 4.0)), Vector3(0.7, 0.7, body_l * 0.7), false)
		for k in 6:
			g.cyl("plate", Transform3D(rot, c + rot * Vector3(beam * 0.25 * (1.0 if k % 2 == 0 else -1.0), top + 0.6, z_mid - body_l * 0.3 + k * body_l * 0.11)), 1.4, 1.0, 10, false)


## Стопка контейнеров на площадке: одиночный ряд (длина вдоль локальной X).
func _cstack(g: Geo, x: float, z: float, yaw: float, levels: int) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var y0 := APRON_H
	for lv in levels:
		var mat: String = CONT_MATS[rng.randi() % 5]
		g.box_xf(mat, Transform3D(rot, Vector3(x, y0 + 1.3 + lv * 2.6, z)), Vector3(6.06, 2.6, 2.44), false)
	g.collider("metal", Transform3D(rot, Vector3(x, y0 + levels * 1.3, z)), Vector3(6.06, levels * 2.6, 2.44))
	for c in [Vector3(3.9, 0, 0), Vector3(-3.9, 0, 0), Vector3(0, 0, 1.9), Vector3(0, 0, -1.9)]:
		cover_points.append(Vector3(x, y0, z) + rot * c)


## Портальный кран на кромке набережной: ось X — вдоль берега, стрела над водой (+Z). collide — ноги с коллизией.
func _crane(g: Geo, x: float, zs: float, collide: bool, y0 := APRON_H) -> void:
	var zl := zs - 22.0
	var mat := "container_blue"
	for sx in [-8.0, 8.0]:
		for zz in [zs, zl]:
			g.box(mat, Vector3(x + sx, y0 + 15.0, zz), Vector3(1.5, 30.0, 1.5), 0.0, collide)
			g.box("plate_dark", Vector3(x + sx, y0 + 0.8, zz), Vector3(2.6, 1.6, 3.0), 0.0, false)
	for zz in [zs, zl]:
		g.box("plate", Vector3(x, y0 + 30.7, zz), Vector3(17.6, 1.8, 1.8), 0.0, false)
		g.box("plate_dark", Vector3(x, y0 + 15.5, zz), Vector3(15.0, 0.9, 0.9), 0.0, false)
		for s in [-1.0, 1.0]:
			g.box("plate_dark", Vector3(x, y0 + 8.0, zz), Vector3(22.6, 0.55, 0.55), 0.0, false, 0.0, 0.785 * s)
			g.box("plate_dark", Vector3(x, y0 + 23.0, zz), Vector3(22.6, 0.55, 0.55), 0.0, false, 0.0, 0.66 * s)
	for sx in [-8.0, 8.0]:
		g.box("plate", Vector3(x + sx, y0 + 30.7, (zs + zl) * 0.5), Vector3(1.8, 1.8, 24.0), 0.0, false)
	# стрела, машинное отделение, тележка с контейнером, мачта и ванты
	g.box("plate", Vector3(x, y0 + 34.0, zs + 21.0), Vector3(2.4, 2.4, 72.0), 0.0, false)
	g.box("plate_dark", Vector3(x, y0 + 33.5, zs - 14.0), Vector3(6.4, 4.0, 9.0), 0.0, false)
	g.box("plate_dark", Vector3(x, y0 + 32.0, zs + 30.0), Vector3(3.4, 1.8, 4.0), 0.0, false)
	g.box("plate_dark", Vector3(x, y0 + 24.0, zs + 30.0), Vector3(2.6, 0.5, 6.2), 0.0, false)
	g.box(CONT_MATS[int(absf(x)) % 4], Vector3(x, y0 + 22.4, zs + 30.0), Vector3(2.44, 2.6, 6.06), 0.0, false)
	g.box("plate", Vector3(x, y0 + 42.0, zs - 6.0), Vector3(1.2, 16.0, 1.2), 0.0, false)
	for s in [-0.8, 0.8]:
		g.box("plate_dark", Vector3(x + s, y0 + 41.0, zs + 28.0), Vector3(0.18, 0.18, 70.0), 0.0, false, 0.14)
		g.box("plate_dark", Vector3(x + s, y0 + 40.0, zs - 24.0), Vector3(0.18, 0.18, 34.0), 0.0, false, -0.28)


# ------------------------------------------------------------------ контейнерный терминал (восток набережной)
func _build_terminal() -> void:
	var saved := rng.state
	rng.seed = 9411
	_gr.seed = 9412
	var parts: Array[Geo] = [Geo.new(), Geo.new(), Geo.new()]
	for pg in parts:
		pg.cast_shadows = false
	var y := APRON_H
	var pitch_x := 24.8
	var pitch_z := 19.6
	var bx := 76.0
	while bx < 300.0:
		var bz := 207.0
		while bz < 337.0:
			var c := Vector2(bx + 9.2, bz + 5.8)
			var gi := 0 if c.x < 150.0 else (1 if c.x < 235.0 else 2)
			# проезд терминала, железная дорога и пропуски через случайные блоки
			var skip := road_dist(c.x, c.y) < 12.0 or rng.randf() < 0.3
			var alongx := rng.randf() < 0.8
			if not skip:
				_cblock(parts[gi], c.x, c.y, alongx, y, 4, 3)
			bz += pitch_z
		bx += pitch_x
	# краны на набережной, один — цель
	_crane(parts[1], 120.0, QZ_FRONT - 3.2, true)
	_crane(parts[2], 275.0, QZ_FRONT - 3.2, true)
	_quay_furniture(parts[1], 70.0, 340.0)
	var oc := Geo.new()
	_crane(oc, CRANE_OBJ_X, QZ_FRONT - 3.2, true)
	crane_node = oc.finish(self, "crane_obj")
	_far(crane_node, 600.0)
	objectives["crane"] = Vector3(CRANE_OBJ_X + 4.0, y + 0.5, QZ_FRONT - 11.0)
	# склад, КПП, техника и укрытия у въезда
	var g := Geo.new()
	var ow := {}
	_garrison(ow, _bld(g, "warehouse", 120.0, 218.0, 0.0, {"w": 26.0, "d": 12.0}, ow), 2, 0, 0, 0)
	var ow2 := {}
	_garrison(ow2, _bld(g, "warehouse", 225.0, 218.0, 0.0, {"w": 22.0, "d": 12.0}, ow2), 2, 0, 0, 0)
	var ob := {}
	_garrison(ob, _bld(g, "booth", 172.0, 203.0, PI * 0.5, {"boom": true}, ob), 1, 0, 0, 0)
	_bld(g, "shed", 300.0, 215.0, 0.0, {"iron": true})
	for b in [[150.0, 205.0, 0.2], [210.0, 207.0, 1.4], [180.0, 345.0, 1.57], [250.0, 345.0, 0.1], [100.0, 345.0, 0.2], [310.0, 330.0, 0.5]]:
		_barrier(g, b[0], b[1], b[2], y)
	for sb in [[140.0, 342.0, 145.0, 342.0], [220.0, 345.0, 225.0, 345.0], [286.0, 300.0, 286.0, 305.0]]:
		_sandbags(g, Vector2(sb[0], sb[1]), Vector2(sb[2], sb[3]), y, 4)
	_wreck(g, 205.0, 343.0, 0.3)
	_wreck(g, 90.0, 200.0, 1.2)
	_truck(g, 140.0, 347.0, 1.57, y)
	_ammo_crate(150.0, 345.0, y, 0.2)
	_ammo_crate(245.0, 343.0, y, 0.9)
	_barrels(305.0, 350.0, 4, y)
	for k in 8:
		_lamp(g, 80.0 + k * 38.0, 358.0, y, PI)
	_far(g.finish(self, "terminal_bld"), 300.0)
	var names := ["terminal_w", "terminal_c", "terminal_e"]
	for i in 3:
		_far(parts[i].finish(self, names[i]), 380.0)
	rng.state = saved


## Блок контейнеров: rows рядов по per штук, ряд — своя высота (1–3), одна коллизия на ряд, углы — укрытия.
func _cblock(g: Geo, cx: float, cz: float, alongx: bool, y0: float, rows: int, per: int) -> void:
	var yaw := 0.0 if alongx else PI * 0.5
	var rot := Basis(Vector3.UP, yaw)
	var rowz := 2.9
	var len := per * 6.2
	for r in rows:
		var lz := (r - (rows - 1) * 0.5) * rowz
		var h := 1 + rng.randi() % 3
		for k in per:
			var lx := (k - (per - 1) * 0.5) * 6.2
			for lv in h:
				var mat: String = CONT_MATS[rng.randi() % 5]
				g.box_xf(mat, Transform3D(rot, Vector3(cx, y0 + 1.3 + lv * 2.6, cz) + rot * Vector3(lx, 0, lz)), Vector3(6.06, 2.6, 2.44), false)
		g.collider("metal", Transform3D(rot, Vector3(cx, y0 + h * 1.3, cz) + rot * Vector3(0, 0, lz)), Vector3(len, h * 2.6, 2.44))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var q := rot * Vector3(sx * (len * 0.5 + 1.3), 0, sz * (rows * rowz * 0.5 + 1.3))
			cover_points.append(Vector3(cx + q.x, y0, cz + q.z))


# ------------------------------------------------------------------ город
func _build_city() -> void:
	var saved := rng.state
	rng.seed = 9511
	_gr.seed = 9512
	# две части по Центральной улице: западная и восточная (каждая рисуется только вблизи)
	var parts: Array[Geo] = [Geo.new(), Geo.new()]
	var r1: PackedVector2Array = roads[1]
	var r2: PackedVector2Array = roads[2]
	var r0: PackedVector2Array = roads[0]
	# Центральная (на север): справа по ходу — восток. z=190 при t=182, z=20 при t=352
	_row(parts[1], r1, 198.0, 1.0, ["block", "shop", "house2", "cafe", "block"], 5.0)
	_row(parts[0], r1, 198.0, -1.0, ["shop", "block", "cafe", "house2", "block"], 5.0)
	_row(parts[1], r1, 368.0, 1.0, ["block", "house2", "shop", "ruin", "block", "house2"], 5.0)
	_row(parts[0], r1, 368.0, -1.0, ["house2", "block", "shop", "cafe", "block", "house"], 5.0)
	# бульвар на восток: справа — юг, слева — север; пересечение с Центральной на t=250
	_row(parts[0], r2, 14.0, 1.0, ["block", "shop", "house2", "block", "cafe"], 6.0)
	_row(parts[0], r2, 14.0, -1.0, ["house2", "block", "shop", "block", "ruin"], 6.0)
	_row(parts[1], r2, 272.0, 1.0, ["block", "shop", "cafe", "block", "house2"], 6.0)
	_row(parts[1], r2, 272.0, -1.0, ["house", "block", "cafe", "block", "shop"], 6.0)
	# проспект вдоль порта: северная сторона (слева по ходу)
	_row(parts[0], r0, 330.0, -1.0, ["block", "house2", "cafe", "block"], 8.0)
	_row(parts[1], r0, 660.0, -1.0, ["shop", "block", "house2", "cafe"], 8.0)
	# баррикады и блокпосты на перекрёстках
	var g := parts[1]
	for it in [[-80.0, 60.0], [-80.0, -80.0], [-80.0, 170.0], [60.0, 20.0], [-190.0, 20.0], [-80.0, -170.0]]:
		var ix: float = it[0]
		var iz: float = it[1]
		_barrier(g, ix - 9.0, iz + 9.0, 0.4, ground(ix - 9.0, iz + 9.0) - 0.05)
		_barrier(g, ix + 9.0, iz - 9.0, -0.5, ground(ix + 9.0, iz - 9.0) - 0.05)
		_sandbags(g, Vector2(ix + 9.0, iz + 9.0), Vector2(ix + 14.0, iz + 9.0), ground(ix + 11.0, iz + 9.0) - 0.1, 4)
		_cover_spots.append(Vector3(ix, iz, 14.0))
	_wreck(g, -60.0, 100.0, 1.57)
	_wreck(g, -100.0, -30.0, 1.57)
	_wreck(g, 70.0, 28.0, 0.1)
	_wreck(g, -230.0, 12.0, 0.2)
	_truck(g, -60.0, -120.0, 1.5, ground(-60.0, -120.0) - 0.05)
	_ammo_crate(-100.0, 100.0, ground(-100.0, 100.0), 0.3)
	_ammo_crate(-60.0, -30.0, ground(-60.0, -30.0), 1.3)
	_ammo_crate(30.0, 40.0, ground(30.0, 40.0), 0.7)
	for k in 10:
		_lamp(g, -100.0 + (k % 2) * 40.0, 150.0 - k * 28.0, ground(-90.0, 150.0 - k * 28.0), 1.57)
	_far(parts[0].finish(self, "city_w"), 290.0)
	_far(parts[1].finish(self, "city_e"), 290.0)
	rng.state = saved


# ------------------------------------------------------------------ промзона (северо-восток)
func _build_industry() -> void:
	var saved := rng.state
	rng.seed = 9611
	_gr.seed = 9612
	var g := Geo.new()
	var g2 := Geo.new()
	var r2: PackedVector2Array = roads[2]
	# вдоль бульвара: слева (север) цеха и склады, справа (юг) гаражи и склады. Дорога идёт на восток с t=0 в x=-330
	_row(g, r2, 560.0, -1.0, [["warehouse", {"w": 30.0, "d": 17.0}], ["warehouse", {"w": 22.0, "d": 12.0}], "garages", ["warehouse", {"w": 24.0, "d": 13.0}], "shed", ["warehouse", {"w": 20.0, "d": 12.0}]], 8.0, 5.0)
	_row(g, r2, 560.0, 1.0, [["warehouse", {"w": 26.0, "d": 13.0}], "garages", ["warehouse", {"w": 22.0, "d": 12.0}], "shed", ["warehouse", {"w": 20.0, "d": 12.0}]], 8.0, 5.0)
	# второй ряд за первым (севернее)
	for it in [[250.0, -75.0, 20.0, 12.0], [330.0, -80.0, 28.0, 14.0], [420.0, -78.0, 22.0, 12.0], [500.0, -70.0, 20.0, 11.0]]:
		var o := {}
		_garrison(o, _bld(g, "warehouse", it[0], it[1], 0.0, {"w": it[2], "d": it[3]}, o), 2, 0, 0, 0)
	# труба и силосы
	var cy := Vector2(380.0, -125.0)
	var gy := ground(cy.x, cy.y)
	g2.cyl("concrete", Transform3D(Basis(), Vector3(cy.x, gy + 20.0, cy.y)), 2.1, 40.0, 14, true, true, 1.5)
	g2.cyl("rust", Transform3D(Basis(), Vector3(cy.x, gy + 40.1, cy.y)), 1.7, 0.4, 14, false)
	for k in 3:
		var sp := Vector2(450.0 + k * 9.0, -130.0)
		var sy := ground(sp.x, sp.y)
		g2.cyl("concrete", Transform3D(Basis(), Vector3(sp.x, sy + 8.0, sp.y)), 3.8, 16.0, 16, true)
		g2.cyl("plate_dark", Transform3D(Basis(), Vector3(sp.x, sy + 16.6, sp.y)), 3.9, 1.2, 16, false, true, 0.6)
	g2.box("rust", Vector3(441.0, ground(441.0, -121.0) + 5.0, -121.0), Vector3(22.0, 0.8, 1.0), 0.0, false)
	# топливные ёмкости, двор: бочки, ящики, мешки, блоки, заборы
	for k in 2:
		var tp := Vector2(300.0 + k * 20.0, 62.0)
		var ty := ground(tp.x, tp.y)
		g2.cyl("container_grey", Transform3D(Basis(), Vector3(tp.x, ty + 2.6, tp.y)), 4.2, 5.2, 16, true)
	for fz in [[240.0, 40.0, 560.0, 40.0], [240.0, 118.0, 560.0, 118.0]]:
		pass
	_fence(g2, Vector2(240.0, 36.0), Vector2(440.0, 36.0), ground(340.0, 36.0))
	_fence(g2, Vector2(470.0, 36.0), Vector2(540.0, 36.0), ground(500.0, 36.0))
	for b in [[260.0, -30.0, 0.2], [340.0, -35.0, 1.3], [420.0, 25.0, 0.1], [500.0, 22.0, 0.4], [300.0, 30.0, 1.5], [470.0, -35.0, 0.6]]:
		_barrier(g, b[0], b[1], b[2], ground(b[0], b[1]) - 0.05)
	for sb in [[290.0, -40.0, 295.0, -40.0], [380.0, 28.0, 385.0, 28.0], [450.0, -38.0, 455.0, -38.0]]:
		_sandbags(g, Vector2(sb[0], sb[1]), Vector2(sb[2], sb[3]), ground(sb[0], sb[1]) - 0.1, 4)
	for c in [[270.0, 28.0, 1.2], [350.0, -42.0, 1.3], [410.0, 30.0, 1.1], [490.0, 26.0, 1.2]]:
		_crate(g, c[0], c[1], c[2], rng.randf_range(-0.4, 0.4), ground(c[0], c[1]) - 0.05)
	_cover_spots.append(Vector3(380.0, -125.0, 12.0))
	_cover_spots.append(Vector3(455.0, -130.0, 16.0))
	_cover_spots.append(Vector3(310.0, 62.0, 14.0))
	for k in 3:
		_barrels(280.0 + k * 90.0, 45.0, 3, ground(280.0 + k * 90.0, 45.0))
	_wreck(g, 360.0, 8.0, 1.57)
	_wreck(g, 480.0, -12.0, 0.2)
	_truck(g, 300.0, -40.0, 0.1, ground(300.0, -40.0) - 0.05)
	_ammo_crate(330.0, 30.0, ground(330.0, 30.0), 0.5)
	_ammo_crate(445.0, 24.0, ground(445.0, 24.0), 1.2)
	_far(g.finish(self, "industry"), 300.0)
	_far(g2.finish(self, "industry_tall"), 700.0)
	rng.state = saved


# ------------------------------------------------------------------ железная дорога
func _build_rail() -> void:
	var g := Geo.new()
	g.cast_shadows = false
	var line: PackedVector2Array = roads[7]
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	var t := 0.0
	var prev := Vector3.ZERO
	var have_prev := false
	while t < total:
		var pd := _line_at(line, t)
		var p: Vector2 = pd[0]
		var dir: Vector2 = pd[1]
		var y := ground(p.x, p.y) + 0.1
		var yaw := atan2(dir.x, dir.y)
		g.box("wood_dark", Vector3(p.x, y + 0.05, p.y), Vector3(2.6, 0.14, 0.3), yaw + PI * 0.5, false)
		var cur := Vector3(p.x, y, p.y)
		if have_prev:
			var seg := cur - prev
			var l := seg.length()
			var pitch := atan2(-seg.y, Vector2(seg.x, seg.z).length())
			var mid := (cur + prev) * 0.5
			var nrm := Vector3(-dir.y, 0, dir.x)
			for s in [-0.72, 0.72]:
				g.box("plate_dark", mid + nrm * s + Vector3(0, 0.2, 0), Vector3(0.1, 0.14, l + 0.05), yaw, false, pitch)
		prev = cur
		have_prev = true
		t += 2.0
	# вагоны на путях: у промзоны и на терминале
	for w in [[500.0, 0.0], [530.0, 0.0], [330.0, 0.0], [290.0, 0.0]]:
		var pd2 := _line_at(line, float(w[0]) + 60.0)
		var wp: Vector2 = pd2[0]
		var wd: Vector2 = pd2[1]
		_wagon(g, wp, atan2(wd.x, wd.y))
	_far(g.finish(self, "rail"), 520.0)


func _wagon(g: Geo, p: Vector2, yaw: float) -> void:
	var y := ground(p.x, p.y) + 0.35
	var rot := Basis(Vector3.UP, yaw)
	var o := Vector3(p.x, y, p.y)
	g.box_xf("rust", Transform3D(rot, o + rot * Vector3(0, 1.8, 0)), Vector3(2.9, 2.6, 12.0), false)
	g.box_xf("plate_dark", Transform3D(rot, o + rot * Vector3(0, 0.6, 0)), Vector3(2.6, 0.5, 13.0), false)
	g.box_xf("plate_dark", Transform3D(rot, o + rot * Vector3(0, 3.2, 0)), Vector3(2.6, 0.2, 11.6), false)
	for bz in [-4.4, 4.4]:
		g.box_xf("plate_dark", Transform3D(rot, o + rot * Vector3(0, 0.3, bz)), Vector3(2.4, 0.5, 2.4), false)
	g.collider("metal", Transform3D(rot, o + rot * Vector3(0, 1.8, 0)), Vector3(2.9, 3.4, 12.6))
	for c in [Vector3(2.2, 0, 4.0), Vector3(-2.2, 0, 4.0), Vector3(2.2, 0, -4.0), Vector3(-2.2, 0, -4.0), Vector3(0, 0, 7.4), Vector3(0, 0, -7.4)]:
		cover_points.append(o + rot * c - Vector3(0, 0.35, 0))


# ------------------------------------------------------------------ нефтебаза (цель)
func _build_oil() -> void:
	var saved := rng.state
	rng.seed = 9711
	_gr.seed = 9712
	var g := Geo.new()
	var gt := Geo.new()
	var c := OIL
	var y: float = pads[2].h
	# резервуары 2 x 3 с обвалованием колонок, трубная эстакада посередине
	for col in 2:
		var tx := c.x - 35.0 + col * 70.0
		_bund(g, tx, c.y, 22.0, 78.0, y)
		for row in 3:
			var tz := c.y - 52.0 + row * 52.0
			var r := 11.5 if row != 1 else 13.0
			gt.cyl("container_grey", Transform3D(Basis(), Vector3(tx, y + 6.0, tz)), r, 12.0, 20, true)
			gt.cyl("plate", Transform3D(Basis(), Vector3(tx, y + 12.9, tz)), r + 0.1, 1.8, 20, false, true, 1.2)
			gt.cyl("plate_dark", Transform3D(Basis(), Vector3(tx, y + 14.0, tz)), 1.0, 0.8, 8, false)
			# лестница по борту
			gt.box("plate_dark", Vector3(tx + r + 0.1, y + 6.0, tz), Vector3(0.9, 12.0, 0.15), 0.0, false)
	for k in 3:
		var pz := c.y - 52.0 + k * 52.0
		gt.box("rust", Vector3(c.x, y + 2.6, pz), Vector3(46.0, 0.45, 0.45), 0.0, false)
		gt.box("rust", Vector3(c.x, y + 3.3, pz + 1.0), Vector3(46.0, 0.35, 0.35), 0.0, false)
		for sx in [-20.0, -6.0, 6.0, 20.0]:
			g.box("plate_dark", Vector3(c.x + sx, y + 1.3, pz), Vector3(0.4, 2.6, 0.5), 0.0, false)
	gt.box("rust", Vector3(c.x, y + 2.6, c.y), Vector3(0.45, 0.45, 112.0), 0.0, false)
	for sz in [-48.0, -20.0, 8.0, 36.0]:
		g.box("plate_dark", Vector3(c.x, y + 1.3, c.y + sz), Vector3(0.5, 2.6, 0.4), 0.0, false)
	# насосная, КПП, эстакада налива, цистерны на колёсах
	var op := {}
	_garrison(op, _bld(g, "warehouse", c.x - 4.0, c.y + 62.0, 0.0, {"w": 16.0, "d": 10.0}, op), 2, 0, 0, 0)
	var ob := {}
	_garrison(ob, _bld(g, "booth", c.x + 12.0, c.y + 70.0, PI * 0.5, {"boom": true}, ob), 1, 0, 0, 0)
	_bld(g, "shed", c.x + 60.0, c.y + 40.0, -PI * 0.5, {"iron": true})
	_bld(g, "shed", c.x - 62.0, c.y + 40.0, PI * 0.5)
	_tower(g, c.x + 70.0, c.y - 70.0, false, y)
	_tower(g, c.x - 72.0, c.y - 68.0, false, y)
	for b in [[c.x - 30.0, c.y + 80.0, 0.1], [c.x + 36.0, c.y + 82.0, -0.2], [c.x, c.y + 50.0, 0.0], [c.x - 70.0, c.y, 1.57], [c.x + 74.0, c.y + 10.0, 1.57]]:
		_barrier(g, b[0], b[1], b[2], y)
	for sb in [[c.x - 50.0, c.y + 88.0, c.x - 44.0, c.y + 88.0], [c.x + 56.0, c.y - 40.0, c.x + 56.0, c.y - 34.0]]:
		_sandbags(g, Vector2(sb[0], sb[1]), Vector2(sb[2], sb[3]), y, 4)
	for k in 3:
		_truck(g, c.x + 60.0, c.y + 56.0 + k * 0.0 - 24.0 + k * 9.0, 0.0, y)
	_barrels(c.x + 40.0, c.y + 62.0, 4, y)
	_ammo_crate(c.x + 4.0, c.y + 52.0, y, 0.4)
	_ammo_crate(c.x - 60.0, c.y - 30.0, y, 1.0)
	_fence(g, Vector2(c.x - 82.0, c.y + 72.0), Vector2(c.x - 14.0, c.y + 72.0), y)
	_fence(g, Vector2(c.x + 12.0, c.y + 72.0), Vector2(c.x + 82.0, c.y + 72.0), y)
	_fence(g, Vector2(c.x - 82.0, c.y - 72.0), Vector2(c.x + 82.0, c.y - 72.0), y)
	_fence(g, Vector2(c.x - 82.0, c.y - 72.0), Vector2(c.x - 82.0, c.y + 72.0), y)
	_fence(g, Vector2(c.x + 82.0, c.y - 72.0), Vector2(c.x + 82.0, c.y + 72.0), y)
	var tanks := gt.finish(self, "oil_tanks")
	_far(tanks, 520.0)
	_burn["fuel"] = [tanks]
	_far(g.finish(self, "oil"), 280.0)
	objectives["fuel"] = Vector3(c.x, y + 0.5, c.y)
	rng.state = saved


## Обвалование колонки резервуаров: стенка 1,3 м с проходами посередине северной и южной сторон.
func _bund(g: Geo, cx: float, cz: float, hx: float, hz: float, y: float) -> void:
	for s in [-1.0, 1.0]:
		var zz: float = cz + s * hz
		for part in [[-1.0], [1.0]]:
			var sx: float = part[0]
			var x0 := cx + sx * 3.5
			var x1 := cx + sx * hx
			g.box("concrete", Vector3((x0 + x1) * 0.5, y + 0.65, zz), Vector3(absf(x1 - x0), 1.3, 0.5), 0.0, true)
			cover_points.append(Vector3((x0 + x1) * 0.5, y, zz - s * 1.0))
		g.box("concrete", Vector3(cx + s * hx, y + 0.65, cz), Vector3(0.5, 1.3, hz * 2.0), 0.0, true)
		cover_points.append(Vector3(cx + s * (hx - 1.0), y, cz))


# ------------------------------------------------------------------ мыс с маяком и радиомаяком (цель)
func _build_lighthouse() -> void:
	var saved := rng.state
	rng.seed = 9811
	_gr.seed = 9812
	var g := Geo.new()
	var c := LIGHT
	var y: float = pads[4].h
	# башня: пять колец белое/красное, галерея, фонарь, крыша
	var seg_h := 5.4
	for k in 5:
		var r0 := lerpf(4.5, 3.0, float(k) / 5.0)
		var r1 := lerpf(4.5, 3.0, float(k + 1) / 5.0)
		var mat := "#e9e4d6" if k % 2 == 0 else "#b03a2e"
		g.cyl(mat, Transform3D(Basis(), Vector3(c.x, y + seg_h * (k + 0.5), c.y)), r0, seg_h, 18, true, true, r1)
	var top := y + seg_h * 5.0
	g.cyl("plate_dark", Transform3D(Basis(), Vector3(c.x, top + 0.15, c.y)), 4.6, 0.3, 18, false)
	g.cyl("!ffe9a8", Transform3D(Basis(), Vector3(c.x, top + 1.5, c.y)), 2.0, 2.4, 14, false)
	g.cyl("roof_red", Transform3D(Basis(), Vector3(c.x, top + 3.6, c.y)), 2.9, 1.8, 14, false, true, 0.3)
	g.box("plate_dark", Vector3(c.x, y + 1.1, c.y + 4.4), Vector3(1.1, 2.2, 0.3), 0.0, false)
	_far(g.finish(self, "lighthouse_tower"), 1000.0)
	g = Geo.new()
	# смотритель и сарай, мешки, ограда
	var oh := {}
	_garrison(oh, _bld(g, "house2", c.x - 24.0, c.y - 10.0, PI * 0.5, {}, oh), 2, 0, 1, 0)
	_bld(g, "shed", c.x + 20.0, c.y + 14.0, -PI * 0.5, {"iron": true})
	var ob := {}
	_garrison(ob, _bld(g, "booth", c.x - 12.0, c.y + 22.0, PI, {"boom": false}, ob), 1, 0, 0, 0)
	_sandbags(g, Vector2(c.x - 12.0, c.y + 14.0), Vector2(c.x - 6.0, c.y + 14.0), y, 4)
	_sandbags(g, Vector2(c.x + 10.0, c.y + 8.0), Vector2(c.x + 16.0, c.y + 8.0), y, 4)
	_barrier(g, c.x + 8.0, c.y - 16.0, 0.4, y)
	_barrier(g, c.x - 6.0, c.y - 20.0, -0.3, y)
	_crate(g, c.x + 14.0, c.y - 6.0, 1.2, 0.3, y)
	_ammo_crate(c.x - 6.0, c.y + 6.0, y, 0.4)
	_far(g.finish(self, "lighthouse"), 250.0)
	# радиомачта рядом (цель)
	var mp := Vector2(c.x + 26.0, c.y - 8.0)
	var my := ground(mp.x, mp.y)
	var mg := Geo.new()
	for sx in [-0.7, 0.7]:
		for sz in [-0.7, 0.7]:
			mg.box("rust", Vector3(mp.x + sx, my + 11.0, mp.y + sz), Vector3(0.12, 22.0, 0.12), 0.0, false)
	for i in 11:
		var by := my + 1.0 + i * 2.0
		mg.box("rust", Vector3(mp.x, by, mp.y - 0.7), Vector3(1.9, 0.06, 0.06), 0.0, false, 0.0, 0.8 if i % 2 == 0 else -0.8)
		mg.box("rust", Vector3(mp.x, by, mp.y + 0.7), Vector3(1.9, 0.06, 0.06), 0.0, false, 0.0, -0.8 if i % 2 == 0 else 0.8)
		mg.box("rust", Vector3(mp.x - 0.7, by, mp.y), Vector3(0.06, 0.06, 1.9), 0.0, false, 0.8 if i % 2 == 0 else -0.8)
		mg.box("rust", Vector3(mp.x + 0.7, by, mp.y), Vector3(0.06, 0.06, 1.9), 0.0, false, -0.8 if i % 2 == 0 else 0.8)
	mg.collider("metal", Transform3D(Basis(), Vector3(mp.x, my + 11.0, mp.y)), Vector3(1.6, 22.0, 1.6))
	mg.box("floor", Vector3(mp.x, my + 0.3, mp.y), Vector3(3.2, 0.2, 3.2))
	mg.box("plate", Vector3(mp.x - 1.0, my + 21.0, mp.y + 0.8), Vector3(0.8, 0.5, 0.3), 0.0, false)
	mg.box("container_green", Vector3(mp.x + 5.0, my + 1.3, mp.y + 2.0), Vector3(2.44, 2.6, 6.06), 0.0, true)
	beacon_node = mg.finish(self, "beacon_mast")
	_far(beacon_node, 700.0)
	beacon_dish = Node3D.new()
	beacon_dish.position = Vector3(mp.x + 1.2, my + 16.0, mp.y + 0.9)
	add_child(beacon_dish)
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
	beacon_dish.add_child(dish)
	var lamp := MeshInstance3D.new()
	var ls := SphereMesh.new()
	ls.radius = 0.14
	ls.height = 0.28
	lamp.mesh = ls
	lamp.material_override = Mats.emissive(Color(1, 0.1, 0.05), 3.0)
	lamp.position = Vector3(mp.x, my + 22.2, mp.y)
	add_child(lamp)
	beacon_lamp = lamp
	objectives["beacon"] = Vector3(mp.x, my + 1.0, mp.y + 2.4)
	rng.state = saved


# ------------------------------------------------------------------ виллы на холмах севера
func _build_villas() -> void:
	var saved := rng.state
	rng.seed = 9911
	_gr.seed = 9912
	var g := Geo.new()
	var g2 := Geo.new()
	var r8: PackedVector2Array = roads[8]
	var r9: PackedVector2Array = roads[9]
	_row(g, r8, 40.0, 1.0, ["house_fence", 18.0, "house2", 22.0, "house", 24.0, "house_fence", 16.0, "house2", 20.0, "house"], 12.0, 6.0)
	_row(g, r8, 55.0, -1.0, ["house2", 20.0, "house_fence", 26.0, "house2", 20.0, "house", 22.0, "house_fence"], 12.0, 6.0)
	_row(g2, r9, 40.0, 1.0, ["house2", 20.0, "house_fence", 24.0, "house", 22.0, "house2", 20.0, "house_fence", 18.0, "house"], 12.0, 6.0)
	_row(g2, r9, 55.0, -1.0, ["house_fence", 24.0, "house2", 20.0, "house", 26.0, "house2", 20.0, "house_fence"], 12.0, 6.0)
	_ammo_crate(150.0, ground(150.0, -318.0), ground(150.0, -318.0) * 0.0 + ground(150.0, -318.0), 0.4)
	_far(g.finish(self, "villas_e"), 230.0)
	_far(g2.finish(self, "villas_w"), 230.0)
	rng.state = saved


func _build_stadium() -> void:
	var saved := rng.state
	rng.seed = 10011
	_gr.seed = 10012
	var g := Geo.new()
	var c := STADIUM
	var y: float = pads[1].h
	objectives["lz"] = Vector3(c.x, y, c.y)
	# разметка поля
	g.box("#d9d6c9", Vector3(c.x, y + 0.03, c.y), Vector3(0.3, 0.04, 48.0), 0.0, false)
	g.box("#d9d6c9", Vector3(c.x, y + 0.03, c.y - 24.0), Vector3(66.0, 0.04, 0.3), 0.0, false)
	g.box("#d9d6c9", Vector3(c.x, y + 0.03, c.y + 24.0), Vector3(66.0, 0.04, 0.3), 0.0, false)
	for s in [-1.0, 1.0]:
		g.box("#d9d6c9", Vector3(c.x + s * 33.0, y + 0.03, c.y), Vector3(0.3, 0.04, 48.0), 0.0, false)
		# ворота
		g.box("plate", Vector3(c.x + s * 33.0, y + 1.2, c.y - 3.7), Vector3(0.16, 2.4, 0.16), 0.0, false)
		g.box("plate", Vector3(c.x + s * 33.0, y + 1.2, c.y + 3.7), Vector3(0.16, 2.4, 0.16), 0.0, false)
		g.box("plate", Vector3(c.x + s * 33.0, y + 2.4, c.y), Vector3(0.16, 0.16, 7.5), 0.0, false)
	# трибуны с севера и юга: три яруса ступеней
	for s in [-1.0, 1.0]:
		for k in 4:
			g.box("concrete", Vector3(c.x, y + 0.3 + k * 0.6, c.y + s * (31.0 + k * 1.6)), Vector3(52.0, 0.6, 1.6), 0.0, true)
		g.box("concrete", Vector3(c.x, y + 1.6, c.y + s * 38.5), Vector3(52.0, 3.2, 0.5), 0.0, true)
		_lamp(g, c.x - 40.0, c.y + s * 28.0, y, 0.0)
		_lamp(g, c.x + 40.0, c.y + s * 28.0, y, PI)
	# посадочные метки, ящики
	for a in 4:
		var ang := a * PI * 0.5 + 0.4
		g.box("#d9d2c0", Vector3(c.x + cos(ang) * 6.0, y + 0.05, c.y + sin(ang) * 6.0), Vector3(2.4, 0.04, 0.5), -ang, false)
	_crate(g, c.x - 12.0, c.y + 8.0, 1.2, 0.2, y)
	_crate(g, c.x + 14.0, c.y - 9.0, 1.3, 0.6, y)
	_ammo_crate(c.x - 8.0, c.y - 8.0, y, 0.8)
	_barrier(g, c.x - 30.0, c.y - 28.0, 0.3, y)
	_barrier(g, c.x + 30.0, c.y + 28.0, 0.3, y)
	_far(g.finish(self, "stadium"), 260.0)
	rng.state = saved


## Опорные точки в поле вокруг районов (гнёзда из мешков, блоки, руины, сгоревшие машины, ящики).
func _build_field_cover() -> void:
	var saved := rng.state
	rng.seed = 52128
	var g := Geo.new()
	var n_ok := 0
	var anchors := [[Vector2(-90.0, 20.0), 235.0, 290.0, 10], [Vector2(260.0, 20.0), 190.0, 250.0, 7], [OIL, 120.0, 170.0, 6],
		[STADIUM, 70.0, 110.0, 5], [LIGHT, 55.0, 95.0, 3], [Vector2(40.0, 286.0), 190.0, 250.0, 2], [SPAWN, 60.0, 110.0, 4], [Vector2(-90.0, -250.0), 70.0, 140.0, 5]]
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
				if road_dist(x, z) < 9.0 or ground(x, z) < 1.6 or _paved(x, z) > 0.2 or not _cover_ok(x, z, 28.0, 6.0):
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
			if _cover_ok(q.x, q.y, 26.0, 4.0) and ground(q.x, q.y) > 1.6:
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
		{"id": "intel", "title": "Забрать разведданные в диспетчерской порта", "pos": objectives.intel, "done": false, "prompt": "Забрать разведданные", "hold": 1.2, "armed": false},
		{"id": "crane", "title": "Подорвать главный портальный кран терминала", "pos": objectives.crane, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "fuel", "title": "Взорвать резервуары нефтебазы", "pos": objectives.fuel, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "beacon", "title": "Уничтожить радиомаяк на мысу у маяка", "pos": objectives.beacon, "done": false, "prompt": "Установить заряд", "hold": 2.5, "armed": false},
		{"id": "lz", "title": "Выйти к точке эвакуации на стадионе", "pos": objectives.lz, "done": false, "locked": true, "prompt": "", "hold": 0.0, "armed": false},
	]


func briefing() -> String:
	return "Противник удерживает портовый город «Северная гавань»: через него идёт снабжение всего побережья. Вы высаживаетесь на юго-западном пляже.\n\n" \
		+ "• Забрать разведданные в диспетчерской торговой гавани (склады и пирсы у воды)\n• Подорвать главный портальный кран контейнерного терминала\n" \
		+ "• Взорвать резервуары нефтебазы на западе города\n• Уничтожить радиомаяк на мысу у маяка (юго-восток)\n• Выйти к точке эвакуации на стадионе на севере\n\n" \
		+ "Контейнеры образуют лабиринт, краны и склады дают высоту. В городе — патрули, на дорогах — машины. К воде не подойти: вдоль берега стоит ограждение."


func _process(delta: float) -> void:
	if beacon_dish and beacon_alive:
		beacon_dish.rotate_y(delta * 0.6)


func destroy_objective(key: String) -> void:
	var burnt := Mats.flat(Color(0.05, 0.045, 0.04), 0.95)
	if key == "beacon":
		beacon_alive = false
		beacon_dish.rotation = Vector3(0.9, beacon_dish.rotation.y, 0.5)
		beacon_dish.position.y -= 3.0
		for c in beacon_dish.get_children():
			(c as MeshInstance3D).material_override = burnt
		beacon_node.material_override = burnt
		beacon_lamp.visible = false
	elif key == "crane":
		crane_node.material_override = burnt
	elif key == "intel":
		intel_node.visible = false
	for n in _burn.get(key, []):
		(n as GeometryInstance3D).material_override = burnt


func bench_views() -> Array:
	return [["пляж, старт", Vector3(-545, 0, 285), Vector3(-450, 3, 215)],
		["пляж, на воду", Vector3(-480, 0, 300), Vector3(-380, 8, 420)],
		["торговая гавань", Vector3(-120, 0, 205), Vector3(-120, 4, 330)],
		["пирсы и суда", Vector3(-150, 0, 372), Vector3(-150, 4, 480)],
		["терминал, контейнеры", Vector3(110, 0, 205), Vector3(250, 3, 300)],
		["кран у набережной", Vector3(150, 0, 350), Vector3(200, 15, 380)],
		["набережная терминала", Vector3(320, 0, 360), Vector3(110, 3, 385)],
		["город, улица Центральная", Vector3(-80, 0, 170), Vector3(-80, 3, 0)],
		["город, перекрёсток", Vector3(-80, 0, 50), Vector3(-80, 3, -70)],
		["бульвар на восток", Vector3(-50, 0, 20), Vector3(150, 3, 10)],
		["промзона", Vector3(190, 0, 40), Vector3(330, 3, -40)],
		["ж/д и силосы", Vector3(300, 0, 110), Vector3(450, 6, -120)],
		["нефтебаза", Vector3(-380, 0, 70), Vector3(-440, 6, -50)],
		["маяк с юго-запада", Vector3(380, 0, 380), Vector3(482, 20, 428)],
		["виллы на холмах", Vector3(120, 0, -100), Vector3(230, 8, -300)],
		["стадион", Vector3(60, 0, -230), Vector3(90, 3, -300)],
		["панорама на порт с севера", Vector3(-20, 0, -150), Vector3(40, 0, 320)]]


# ------------------------------------------------------------------ машины
## Индексы дорог: 0 проспект, 1 Центральная, 2 бульвар, 3 к нефтебазе, 4 терминал, 5 пирс, 6 маяк, 7 рельсы, 8 и 9 виллы.
func _define_vehicles() -> void:
	vehicle_spots = [
		[Vector3(-520, 0, 232), 0.2, "civ"], [Vector3(-440, 0, 225), 0.3, "civ"], [Vector3(-330, 0, 205), 0.4, "civ"],
		[Vector3(-85, 0, 120), 1.57, "civ"], [Vector3(-75, 0, 60), 1.57, "civ"], [Vector3(-76, 0, -80), 1.5, "civ"], [Vector3(-150, 0, 26), 0.0, "civ"],
		[Vector3(20, 0, 24), 0.0, "civ"], [Vector3(-80, 0, 260), 1.57, "mil"], [Vector3(-150, 0, 262), 0.0, "mil"], [Vector3(-60, 0, 330), 1.5, "mil"],
		[Vector3(130, 0, 200), 0.0, "mil"], [Vector3(230, 0, 345), 1.5, "mil"], [Vector3(100, 0, 345), 0.0, "any"], [Vector3(310, 0, 215), 1.2, "mil"],
		[Vector3(250, 0, 8), 0.0, "mil"], [Vector3(400, 0, 8), 0.0, "any"], [Vector3(330, 0, 40), 1.5, "civ"],
		[Vector3(OIL.x + 20.0, 0, OIL.y + 90.0), 0.3, "mil"], [Vector3(-420, 0, 60), 0.5, "mil"], [Vector3(450, 0, 392), 0.8, "mil"],
		[Vector3(220, 0, -95), 1.2, "civ"], [Vector3(-160, 0, -112), 1.0, "civ"], [Vector3(60, 0, -300), 1.5, "any"],
	]
	vehicle_patrols = [[0, 2], [1, 2]]
	vehicle_fill = 0.5


## Случайная точка появления: как в базовой карте, но только на суше (не в воде и не на пирсах).
func random_spawn() -> Array:
	var res: Array = super.random_spawn()
	for i in 24:
		var p: Vector3 = res[0]
		if p.y > 1.6 and _paved(p.x, p.z) < 0.3:
			return res
		res = super.random_spawn()
	return [Vector3(spawn_point.x, spawn_point.y, spawn_point.z), 0.0]


## Картинка карты: море закрашивается (в базовой его нет), пирсы и набережная — бетон.
func bake_map_image() -> void:
	super.bake_map_image()
	var path := ProjectSettings.globalize_path("user://map_%s.png" % map_key)
	var img := Image.load_from_file(path)
	if img == null:
		return
	var T := MAP_TEX
	var half := map_half()
	var step := half * 2.0 / T
	var sea := Color(0.2, 0.42, 0.55)
	var deck := Color(0.62, 0.61, 0.58)
	for j in T:
		for i in T:
			var wx := (i + 0.5) * step - half
			var wz := (j + 0.5) * step - half
			var on_deck := wx >= QUAY_X0 and wx <= QUAY_X1 and wz <= QZ_FRONT
			for p in PIERS:
				if absf(wx - float(p[0])) <= float(p[2]) * 0.5 and wz >= QZ_FRONT - 4.0 and wz <= float(p[1]):
					on_deck = true
			if on_deck and wz > QZ - 4.0:
				img.set_pixel(i, j, deck)
			elif ground(wx, wz) < 0.0 and not on_deck:
				var cur := img.get_pixel(i, j)
				var lum := (cur.r + cur.g + cur.b) / 3.0
				img.set_pixel(i, j, sea.lerp(cur, 0.12) * (0.8 + lum * 0.35))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	ResourceSaver.save(tex, map_tex_path(map_key))
	img.save_png(path)


# ------------------------------------------------------------------ противники
func _define_enemies() -> void:
	_thin.seed = 5711
	# пляж (старт): патруль по набережной и вышки, редкие посты
	_e(-440.0, 250.0, 90, 0, [[-500.0, 255.0], [-380.0, 235.0]])
	_e(-470.0, 305.0, 180, 2, [], ground(-470.0, 305.0) + 5.1, true)
	_e(-380.0, 280.0, 180, 2, [], ground(-380.0, 280.0) + 5.1, true)
	_e(-410.0, 262.0, 200, 0)
	_e(-330.0, 235.0, 180, 1)
	_e(-430.0, 215.0, 150, 0)
	# торговая гавань: КПП, склады, пирсы
	_e(-82.0, 214.0, 180, 0)
	_e(-70.0, 212.0, 180, 1)
	_e(-150.0, 205.0, 180, 0)
	_e(-110.0, 240.0, 150, 1)
	_e(-100.0, 260.0, 0, 0, [[-230.0, 262.0], [-30.0, 262.0], [-40.0, 300.0], [-230.0, 300.0]])
	_e(-60.0, 275.0, 200, 0)
	_e(-190.0, 275.0, 150, 0)
	_e(-130.0, 300.0, 180, 1)
	_e(-200.0, 400.0, 180, 0)
	_e(-196.0, 470.0, 180, 1, [], APRON_H + 0.05)
	_e(-105.0, 440.0, 180, 0, [], APRON_H + 0.05)
	_e(-100.0, 505.0, 180, 2, [], APRON_H + 0.05, true)
	_e(-10.0, 450.0, 180, 0, [], APRON_H + 0.05)
	_e(-182.0, 440.0, 180, 2, [], 5.6, true)
	_e(10.0, 440.0, 180, 2, [], 5.6, true)
	# контейнерный терминал: перекрёстки проездов
	var jx := [88.0, 113.0, 138.0, 163.0, 213.0, 238.0, 288.0]
	var jz := [203.0, 223.0, 243.0, 262.0, 282.0, 302.0, 321.0, 341.0]
	_e(jx[0] as float, jz[1] as float, 90, 0)
	_e(jx[1] as float, jz[3] as float, 0, 1)
	_e(jx[2] as float, jz[5] as float, 180, 0)
	_e(jx[3] as float, jz[2] as float, 90, 0)
	_e(jx[4] as float, jz[1] as float, 270, 0)
	_e(jx[5] as float, jz[4] as float, 0, 1)
	_e(jx[6] as float, jz[3] as float, 270, 0)
	_e(jx[4] as float, jz[6] as float, 180, 0)
	_e(jx[1] as float, jz[7] as float, 180, 0)
	_e(jx[5] as float, jz[7] as float, 180, 1)
	_e(150.0, 275.0, 90, 0, [[95.0, 262.0], [170.0, 262.0], [170.0, 340.0], [95.0, 340.0]])
	_e(250.0, 300.0, 270, 0, [[300.0, 282.0], [230.0, 282.0], [230.0, 340.0], [300.0, 340.0]])
	_e(180.0, 330.0, 90, 0, [[180.0, 210.0], [180.0, 345.0]])
	_e(CRANE_OBJ_X - 12.0, 365.0, 180, 0)
	_e(CRANE_OBJ_X + 14.0, 360.0, 180, 1)
	_e(190.0, 372.0, 180, 0)
	_e(120.0, 366.0, 0, 2, [], APRON_H + 0.05, true)
	_e(280.0, 366.0, 0, 0)
	_e(200.0, 405.0, 180, 2, [], 5.6, true)
	# город: перекрёстки, улицы
	_e(-84.0, 172.0, 180, 0)
	_e(-70.0, 168.0, 180, 1)
	_e(-84.0, 62.0, 180, 0)
	_e(-68.0, 56.0, 150, 0)
	_e(-84.0, -76.0, 0, 0)
	_e(-70.0, -82.0, 0, 1)
	_e(-80.0, 120.0, 0, 0, [[-80.0, 175.0], [-80.0, 40.0]])
	_e(-78.0, -20.0, 180, 0, [[-80.0, 45.0], [-80.0, -130.0]])
	_e(-200.0, 22.0, 90, 0, [[-300.0, 22.0], [-100.0, 22.0]])
	_e(40.0, 22.0, 270, 0, [[-60.0, 22.0], [120.0, 18.0]])
	_e(-190.0, 24.0, 90, 0)
	_e(60.0, 16.0, 270, 1)
	_e(-150.0, 100.0, 0, 0, [[-190.0, 120.0], [-110.0, 80.0], [-170.0, 40.0]])
	_e(10.0, 80.0, 0, 0, [[40.0, 120.0], [30.0, 40.0], [-30.0, 70.0]])
	_e(-190.0, -80.0, 0, 0, [[-230.0, -60.0], [-150.0, -100.0], [-120.0, -30.0]])
	_e(20.0, -80.0, 0, 0, [[-20.0, -120.0], [60.0, -60.0]])
	_e(-130.0, 60.0, 90, 2, [], -1000.0, true)
	_e(-30.0, -40.0, 270, 2, [], -1000.0, true)
	# промзона и ж/д
	_e(280.0, -8.0, 90, 0)
	_e(330.0, 10.0, 270, 1)
	_e(430.0, -10.0, 90, 0)
	_e(480.0, 8.0, 270, 0)
	_e(300.0, 0.0, 0, 0, [[250.0, 0.0], [350.0, 0.0], [430.0, 3.0], [520.0, -2.0]])
	_e(350.0, 100.0, 0, 0, [[300.0, 120.0], [420.0, 120.0], [500.0, 125.0]])
	_e(330.0, 52.0, 180, 0)
	_e(420.0, 80.0, 0, 1)
	_e(385.0, -115.0, 180, 0)
	_e(455.0, -120.0, 180, 1)
	_e(380.0, -128.0, 0, 2, [], ground(380.0, -125.0) + 41.0, true)
	_e(300.0, -60.0, 90, 0)
	_e(520.0, 40.0, 270, 0)
	# нефтебаза
	var oc := OIL
	_e(oc.x - 40.0, oc.y + 80.0, 180, 0)
	_e(oc.x + 40.0, oc.y + 82.0, 180, 1)
	_e(oc.x, oc.y - 80.0, 0, 0)
	_e(oc.x - 78.0, oc.y - 20.0, 270, 0)
	_e(oc.x + 78.0, oc.y + 10.0, 90, 0)
	_e(oc.x, oc.y - 20.0, 0, 0, [[oc.x - 35.0, oc.y - 70.0], [oc.x + 35.0, oc.y - 70.0], [oc.x + 35.0, oc.y + 60.0], [oc.x - 35.0, oc.y + 60.0]])
	_e(oc.x + 8.0, oc.y + 10.0, 90, 0)
	_e(oc.x - 8.0, oc.y - 40.0, 0, 1)
	_e(oc.x, oc.y + 30.0, 180, 2, [], -1000.0, true)
	_e(-400.0, 80.0, 0, 0, [[-420.0, 60.0], [-340.0, 125.0]])
	# маяк
	var lc := LIGHT
	_e(lc.x + 10.0, lc.y + 14.0, 180, 0)
	_e(lc.x - 18.0, lc.y - 22.0, 270, 1)
	_e(lc.x + 30.0, lc.y + 6.0, 90, 0)
	_e(lc.x, lc.y + 2.0, 180, 2, [], -1000.0, true)
	_e(lc.x - 10.0, lc.y - 10.0, 0, 0, [[lc.x - 30.0, lc.y - 15.0], [lc.x + 20.0, lc.y - 25.0], [lc.x + 20.0, lc.y + 12.0]])
	_e(400.0, 340.0, 180, 0, [[380.0, 340.0], [440.0, 390.0]])
	# виллы и стадион
	_e(220.0, -90.0, 0, 0, [[200.0, -60.0], [250.0, -170.0]])
	_e(250.0, -250.0, 0, 0, [[255.0, -200.0], [220.0, -310.0]])
	_e(-200.0, -200.0, 0, 0, [[-225.0, -150.0], [-230.0, -270.0]])
	_e(-120.0, -350.0, 0, 0, [[-170.0, -360.0], [-70.0, -350.0]])
	var sc := STADIUM
	_e(sc.x - 30.0, sc.y - 22.0, 180, 0)
	_e(sc.x + 28.0, sc.y + 22.0, 0, 1)
	_e(sc.x, sc.y + 34.0, 180, 0)
	_e(sc.x + 34.0, sc.y - 10.0, 90, 0)
	_e(sc.x - 20.0, sc.y + 40.0, 0, 2, [], -1000.0, true)
	_e(sc.x, sc.y, 0, 0, [[sc.x - 20.0, sc.y - 15.0], [sc.x + 20.0, sc.y + 12.0]])
	_e(-40.0, -280.0, 0, 0, [[-60.0, -265.0], [30.0, -300.0]])
	_e(-20.0, -230.0, 90, 0)
