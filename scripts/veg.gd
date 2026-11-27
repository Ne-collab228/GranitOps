class_name Veg
extends RefCounted
## Растительность из запечённых карточек (CC0: Poly Haven, ambientCG — см. assets/veg/LICENSES.txt).
## Атласы и размеры — tools/bake_veg.gd -> tools/veg_pack.py (assets/veg/*, scripts/veg_data.gd).
##
## Каждая функция возвращает словарь:
##   mesh: ArrayMesh (одна поверхность), mat: ShaderMaterial (общий на атлас), height, radius (м),
##   tris, shadow (отбрасывать ли тень), vis_begin/vis_end (рекомендуемые дальности, м), variants.
## Ставить через MultiMesh (Veg.multimesh) с material_override = mat. Цвет экземпляра (use_colors):
##   rgb — оттенок (умножается на текстуру), a — номер варианта (Veg.inst_color), у травы 4 варианта.
##
## LOD деревьев: два MultiMeshInstance3D на одни и те же преобразования:
##   ближний tree(k, 0): visibility_range_end = d, margin 4;  дальний tree(k, 1): visibility_range_begin = d, margin 4.
##   Дальность видимости MultiMesh считается по центру его AABB (всего куска!), поэтому деревья — кусками 40–60 м.

const D := preload("res://scripts/veg_data.gd")

const TREES := ["broadleaf", "searsia", "fir", "dead"]
const SHRUBS := ["shrub_02", "shrub_03", "rooibos", "fern", "lucida"]
## Варианты травы (строки атласа): 0 зелёная, 1 сухая, 2 смешанная, 3 с цветами/низкая.
const GRASS_VARIANTS := 4
## Общий оттенок вида (умножается на атлас): ель у саженца Poly Haven слишком салатовая.
const TREE_TINT := {"broadleaf": Color(0.86, 0.9, 0.8), "searsia": Color(0.9, 0.92, 0.85),
	"fir": Color(0.6, 0.72, 0.64), "dead": Color(0.82, 0.76, 0.72)}

const SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque%s;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float normal_depth = 1.0;
uniform float alpha_cut = 0.5;
uniform float tex_px = 1024.0;
uniform float wind = 1.0;
uniform float wind_amp = 0.1;
uniform float wind_h = 1.0;
uniform float wind_speed = 1.0;
uniform vec3 backlight_col : source_color = vec3(0.3, 0.32, 0.16);
uniform float variants = 1.0;
uniform vec2 variant_step = vec2(0.0);
uniform vec4 bark_rect = vec4(-1.0);
uniform float rough = 0.9;
uniform float spec = 0.12;
uniform vec3 tint : source_color = vec3(1.0);
// «объёмная» нормаль кроны: из настоящего положения точки относительно центра кроны (в координатах модели).
// Одинакова на пересекающихся карточках — швов освещения нет.
uniform vec3 crown_c = vec3(0.0, 1.0, 0.0);
uniform vec3 crown_ext = vec3(1.0);
uniform float sphere_k = 0.5;
varying float v_bark;
varying vec3 v_sph;

void vertex() {
	float vi = clamp(floor((1.0 - COLOR.a) * variants + 0.001), 0.0, max(variants - 1.0, 0.0));
	UV += variant_step * vi;
	v_bark = step(bark_rect.x, UV.x) * step(bark_rect.y, UV.y) * step(UV.x, bark_rect.z) * step(UV.y, bark_rect.w);
	v_sph = (VERTEX - crown_c) / (crown_ext * crown_ext);
	// бинормаль = «вверх по картинке» (карточки запечены с нормалями в осях кадра)
	BINORMAL = normalize(cross(NORMAL, TANGENT));
	if (wind > 0.0) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float h = clamp(VERTEX.y / wind_h, 0.0, 1.4);
		float t = TIME * wind_speed + o.x * 0.21 + o.z * 0.17;
		float g = sin(t * 1.3) * 0.55 + sin(t * 2.9 + 1.7) * 0.25 + sin(t * 0.43) * 0.5 + 0.35;
		VERTEX.xz += vec2(g, sin(t * 1.1 + 0.6) * 0.45) * (wind_amp * h * h);
	}
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * tint;
	// на дальних мипах альфа «тает» — поднимаем её с уровнем мипа
	vec2 d = fwidth(UV) * tex_px;
	float lod = max(log2(max(max(d.x, d.y), 1e-4)), 0.0);
	float a = t.a * (1.0 + lod * 0.28);
	// карточка ребром к камере растворяется — её закрывают соседние (пороги в UV2, у ствола UV2.x < 0)
	if (UV2.x >= 0.0) {
		a *= smoothstep(UV2.x, UV2.y, abs(dot(NORMAL, VIEW)));
	}
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec2 nm = texture(normal_tex, UV).xy * 2.0 - 1.0;
	nm *= normal_depth;
	vec3 n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * sqrt(max(1.0 - dot(nm, nm), 0.0)));
	vec3 s = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(v_sph, 0.0))).xyz);
	NORMAL = normalize(mix(n, s, sphere_k * (1.0 - v_bark)));
	ROUGHNESS = rough;
	SPECULAR = spec;
	BACKLIGHT = backlight_col * (1.0 - v_bark);
}
"""

static var _shaders := {}
static var _mats := {}
static var _cache := {}
static var wind_on := true
static var normals_on := true


## Дерево: kind из TREES; lod 0 — вблизи (ствол-цилиндр + 3 карточки + горизонтальная), 1 — вдали (3 карточки).
static func tree(kind: String, lod := 0) -> Dictionary:
	var key := "t_%s_%d" % [kind, lod]
	if _cache.has(key):
		return _cache[key]
	var d: Dictionary = D.DATA[kind]
	var st := _begin()
	var tris := 0
	for v in d.views:
		tris += _card(st, v, 2 if lod == 0 else 1)
	if lod == 0 and d.has("top"):
		tris += _top_card(st, d.top)
	if lod == 0 and d.has("bark"):
		tris += _trunk(st, d.trunk, d.bark, 7)
	var h: float = d.height
	var cy0: float = d.crown_y0
	var cy1: float = d.crown_y1
	var cr: float = d.radius
	var m := _mat(kind, {"wind_amp": h * 0.012, "wind_h": h, "wind_speed": 0.8,
		"backlight_col": Color(0.1, 0.1, 0.05) if kind == "dead" else Color(0.2, 0.22, 0.09),
		"crown_c": Vector3(0, lerpf(cy0, cy1, 0.45 if kind == "fir" else 0.55), 0),
		"crown_ext": Vector3(cr * 0.75, (cy1 - cy0) * 0.55, cr * 0.75),
		"sphere_k": 0.25 if kind == "dead" else 0.55, "tint": TREE_TINT[kind]})
	var near := {"broadleaf": 80.0, "searsia": 60.0, "fir": 80.0, "dead": 70.0}
	var r := {"mesh": st.commit(), "mat": m, "height": h, "radius": float(d.radius), "tris": tris,
		"shadow": true, "variants": 1,
		"vis_begin": 0.0 if lod == 0 else near[kind], "vis_end": near[kind] if lod == 0 else 450.0}
	_cache[key] = r
	return r


## Куст: kind из SHRUBS. 3 скрещённые карточки (по 2 треугольника на ярус).
static func shrub(kind: String) -> Dictionary:
	var key := "s_" + kind
	if _cache.has(key):
		return _cache[key]
	var d: Dictionary = D.DATA[kind]
	var st := _begin()
	var tris := 0
	var h: float = d.height
	for v in d.views:
		tris += _card(st, v, 2 if h > 1.0 else 1)
	# у кустов общий атлас и материал: «объёмная» нормаль — от точки под землёй (почти вверх и наружу)
	var m := _mat("shrubs", {"wind_amp": 0.05, "wind_h": 1.0, "wind_speed": 1.2,
		"crown_c": Vector3(0, -0.3, 0), "crown_ext": Vector3(1, 1.2, 1), "sphere_k": 0.45, "tint": Color(0.88, 0.9, 0.84)})
	var r := {"mesh": st.commit(), "mat": m, "height": h, "radius": float(d.radius), "tris": tris,
		"shadow": h > 1.2, "variants": 1, "vis_begin": 0.0, "vis_end": clampf(60.0 + h * 60.0, 60.0, 220.0)}
	_cache[key] = r
	return r


## Пучок травы ~1 x 0.5 м: 3 карточки по 60° с разными кадрами, 2 яруса (изгиб на ветру) — 12 треугольников.
## Вариант (зелёная/сухая/смешанная/цветы) — альфа цвета экземпляра: Veg.inst_color(оттенок, вариант).
static func grass() -> Dictionary:
	if _cache.has("g"):
		return _cache["g"]
	var d: Dictionary = D.DATA["grass"]
	var w: float = d.w
	var hh: float = d.h
	var fw := 1.0 / float(d.cols)
	var fh := 1.0 / float(d.rows)
	var st := _begin()
	var cols := [0, 1, 0]
	for i in 3:
		var u0: float = cols[i] * fw + 0.002
		var u1: float = (cols[i] + 1) * fw - 0.002
		if i == 2:  # третья карточка — зеркальный первый кадр
			var tmp := u0
			u0 = u1
			u1 = tmp
		var v := {"yaw": 60.0 * i + 15.0, "x0": -w * 0.5, "x1": w * 0.5, "y0": -0.04, "y1": hh - 0.04,
			"uv": [u0, 0.003, u1, fh - 0.002]}
		_card(st, v, 2, Vector2(0.02, 0.2))
	var m := _mat("grass", {"wind_amp": 0.09, "wind_h": hh, "wind_speed": 1.6, "variants": float(GRASS_VARIANTS),
		"variant_step": Vector2(0, fh), "backlight_col": Color(0.35, 0.36, 0.18), "receive_shadows": true,
		"crown_c": Vector3(0, -0.5, 0), "crown_ext": Vector3(1, 1, 1), "sphere_k": 0.6,
		"alpha_cut": 0.45, "rough": 0.95, "tint": Color(0.9, 0.88, 0.84)})
	var r := {"mesh": st.commit(), "mat": m, "height": hh, "radius": w * 0.5, "tris": 12, "shadow": false,
		"variants": GRASS_VARIANTS, "vis_begin": 0.0, "vis_end": 45.0}
	_cache["g"] = r
	return r


## Цвет экземпляра MultiMesh: оттенок + номер варианта в альфе (у травы: 0 зелёная, 1 сухая, 2 смешанная, 3 цветы/низкая).
static func inst_color(tint: Color, variant := 0, variants := GRASS_VARIANTS) -> Color:
	return Color(tint.r, tint.g, tint.b, 1.0 - (float(variant) + 0.5) / float(variants))


## Готовый MultiMeshInstance3D: info — результат tree/shrub/grass; colors — пусто или по цвету на экземпляр.
static func multimesh(info: Dictionary, xforms: Array, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = info.mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = info.mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if info.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = info.vis_begin
	mmi.visibility_range_end = info.vis_end
	mmi.visibility_range_begin_margin = 4.0 if info.vis_begin > 0.0 else 0.0
	mmi.visibility_range_end_margin = 4.0
	return mmi


## Ветер (качание верхушек в вершинном шейдере) — вкл/выкл для всех материалов растительности.
static func set_wind(on: bool) -> void:
	wind_on = on
	for k in _mats:
		(_mats[k] as ShaderMaterial).set_shader_parameter("wind", 1.0 if on else 0.0)


## Карты нормалей (объём кроны). Выключение экономит выборку текстуры на слабом GPU.
static func set_normals(on: bool) -> void:
	normals_on = on
	for k in _mats:
		(_mats[k] as ShaderMaterial).set_shader_parameter("normal_depth", 1.0 if on else 0.0)


# ---------------------------------------------------------------- внутреннее

static func _mat(atlas: String, params: Dictionary) -> ShaderMaterial:
	if _mats.has(atlas):
		return _mats[atlas]
	# деревья и кусты не принимают тени: самозатенение запечено, а тени карточек друг на друге дают прямые края
	var recv: bool = params.get("receive_shadows", false)
	params.erase("receive_shadows")
	if not _shaders.has(recv):
		var sh := Shader.new()
		sh.code = SHADER % ("" if recv else ", shadows_disabled")
		_shaders[recv] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[recv]
	var tex: Texture2D = load("res://assets/veg/%s_col.png" % atlas)
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("normal_tex", load("res://assets/veg/%s_nor.png" % atlas))
	m.set_shader_parameter("tex_px", float(tex.get_width()))
	m.set_shader_parameter("wind", 1.0 if wind_on else 0.0)
	m.set_shader_parameter("normal_depth", 1.0 if normals_on else 0.0)
	var d: Dictionary = D.DATA.get(atlas, {})
	if d.has("bark"):
		var b: Array = d.bark
		m.set_shader_parameter("bark_rect", Vector4(b[0], b[1], b[2], b[3]))
	for k in params:
		m.set_shader_parameter(k, params[k])
	_mats[atlas] = m
	return m


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Вертикальная карточка вида v (поворот yaw вокруг оси, метры кадра x0..x1, y0..y1); rows — ярусов по высоте.
static func _card(st: SurfaceTool, v: Dictionary, rows: int, fade := Vector2(0.05, 0.3)) -> int:
	var a := deg_to_rad(float(v.yaw))
	var t := Vector3(cos(a), 0.0, -sin(a))
	var n := Vector3(sin(a), 0.0, cos(a))
	var uv: Array = v.uv
	var x0: float = v.x0
	var x1: float = v.x1
	var y0: float = v.y0
	var y1: float = v.y1
	for r in rows:
		var f0 := float(r) / rows
		var f1 := float(r + 1) / rows
		var ya := lerpf(y0, y1, f0)
		var yb := lerpf(y0, y1, f1)
		var va := lerpf(uv[3], uv[1], f0)
		var vb := lerpf(uv[3], uv[1], f1)
		var p := [t * x0 + Vector3(0, ya, 0), t * x1 + Vector3(0, ya, 0), t * x1 + Vector3(0, yb, 0), t * x0 + Vector3(0, yb, 0)]
		var q := [Vector2(uv[0], va), Vector2(uv[2], va), Vector2(uv[2], vb), Vector2(uv[0], vb)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_tangent(Plane(t, 1.0))
			st.set_uv(q[k])
			st.set_uv2(fade)
			st.add_vertex(p[k])
	return rows * 2


## Горизонтальная карточка (вид сверху): вверх по картинке = −Z.
static func _top_card(st: SurfaceTool, v: Dictionary) -> int:
	var uv: Array = v.uv
	var y: float = v.y
	var p := [Vector3(v.x0, y, v.z1), Vector3(v.x1, y, v.z1), Vector3(v.x1, y, v.z0), Vector3(v.x0, y, v.z0)]
	var q := [Vector2(uv[0], uv[3]), Vector2(uv[2], uv[3]), Vector2(uv[2], uv[1]), Vector2(uv[0], uv[1])]
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_tangent(Plane(Vector3.RIGHT, 1.0))
		st.set_uv(q[k])
		st.set_uv2(Vector2(0.5, 0.8))  # видна, только если смотреть круто снизу/сверху
		st.add_vertex(p[k])
	return 2


## Ствол: усечённый конус в 2 яруса с прикорневым расширением; кора — полоса атласа (u — вокруг, v — вверх).
static func _trunk(st: SurfaceTool, tr: Array, bark: Array, sides: int) -> int:
	var r0: float = tr[0]
	var th: float = tr[1]
	var rings := [[-0.25, r0 * 1.3], [th * 0.45, r0 * 0.82], [th, r0 * 0.5]]
	for ri in rings.size() - 1:
		var ya: float = rings[ri][0]
		var ra: float = rings[ri][1]
		var yb: float = rings[ri + 1][0]
		var rb: float = rings[ri + 1][1]
		var va: float = lerpf(bark[3], bark[1], (ya + 0.25) / (th + 0.25))
		var vb: float = lerpf(bark[3], bark[1], (yb + 0.25) / (th + 0.25))
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			# снаружи угол растёт справа налево — u идёт обратно, чтобы кора не была зеркальной
			var u0: float = lerpf(bark[2], bark[0], float(i) / sides)
			var u1: float = lerpf(bark[2], bark[0], float(i + 1) / sides)
			var pts := [
				[Vector3(cos(a0) * ra, ya, sin(a0) * ra), a0, Vector2(u0, va)],
				[Vector3(cos(a1) * ra, ya, sin(a1) * ra), a1, Vector2(u1, va)],
				[Vector3(cos(a1) * rb, yb, sin(a1) * rb), a1, Vector2(u1, vb)],
				[Vector3(cos(a0) * rb, yb, sin(a0) * rb), a0, Vector2(u0, vb)],
			]
			for k in [0, 1, 2, 0, 2, 3]:  # по часовой при взгляде снаружи
				var ang: float = pts[k][1]
				st.set_normal(Vector3(cos(ang), 0.15, sin(ang)).normalized())
				# касательная — по обходу (u растёт), бинормаль (вверх) шейдер получает как N x T
				st.set_tangent(Plane(Vector3(sin(ang), 0.0, -cos(ang)), 1.0))
				st.set_uv(pts[k][2])
				st.set_uv2(Vector2(-1.0, -1.0))
				st.add_vertex(pts[k][0])
	return (rings.size() - 1) * sides * 2
