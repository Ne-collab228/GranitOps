extends SceneTree
## Запекание растительности в карточки (альбедо + нормали) из glTF Poly Haven и травинок ambientCG.
## Сначала: python -I tools/veg_prep.py <staging> <проект>   (исходники -> tools/_veg_src)
## Запуск (окно маленькое, в углу):
##   G --path . --resolution 640x480 --position 20,40 -s res://tools/bake_veg.gd [-- --only=имя,имя]
## Результат: tools/_veg_bake/<имя>_<вид>_col.png / _nor.png + <имя>.json (метры кадра),
## дальше python -I tools/veg_pack.py <проект> собирает атласы в assets/veg и scripts/veg_data.gd.
##
## Альбедо — без освещения, с мягким «объёмным» затенением кроны (глубже в кроне и снизу темнее);
## нормали — в пространстве кадра (x вправо, y вверх, z на камеру), у листвы смешаны со «сферической»
## нормалью кроны: билборд освещается как объём, а не как плоскость.

const SRC := "res://tools/_veg_src/"
const OUT := "res://tools/_veg_bake/"

# kind: tree — 3 вида сбоку (0/60/120°) + сверху; shrub — 3 вида сбоку.
# nodes — подстроки имён узлов (из многовариантных файлов берётся один вариант), hide — материалы, которые скрыть.
# height — итоговая высота в метрах (масштаб), ao — сила затенения кроны, cell — размер вида в атласе.
const JOBS := [
	{"name": "broadleaf", "kind": "tree", "src": "jacaranda_tree", "nodes": [], "hide": [], "height": 11.0, "ao": 0.68, "cell": 1024},
	{"name": "dead", "kind": "tree", "src": "jacaranda_tree", "nodes": [], "hide": ["leaves"], "height": 9.5, "ao": 0.3, "cell": 1024},
	{"name": "searsia", "kind": "tree", "src": "searsia_burchellii", "nodes": ["large"], "hide": [], "height": 5.2, "ao": 0.62, "cell": 512},
	{"name": "fir", "kind": "tree", "src": "fir_sapling_medium", "nodes": ["_a_"], "hide": [], "height": 12.0, "ao": 0.66, "cell": 1024, "dup": 2},
	{"name": "shrub_02", "kind": "shrub", "src": "shrub_02", "nodes": ["_a"], "hide": [], "height": 0.0, "ao": 0.45, "cell": 512},
	{"name": "shrub_03", "kind": "shrub", "src": "shrub_03", "nodes": ["_a"], "hide": [], "height": 0.0, "ao": 0.35, "cell": 512},
	{"name": "rooibos", "kind": "shrub", "src": "wild_rooibos_bush", "nodes": ["_a"], "hide": [], "height": 0.0, "ao": 0.45, "cell": 512},
	{"name": "fern", "kind": "shrub", "src": "fern_02", "nodes": ["_b"], "hide": [], "height": 0.0, "ao": 0.35, "cell": 512},
	{"name": "lucida", "kind": "shrub", "src": "searsia_lucida", "nodes": ["_a_"], "hide": [], "height": 0.0, "ao": 0.5, "cell": 512},
	{"name": "grass", "kind": "grass"},
]

const SS := 3  # суперсэмплинг (уменьшение — в veg_pack.py)

const BAKE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform int mode = 0;          // 0 альбедо, 1 нормали
uniform float cut = 0.0;       // 1 — альфа-тест (листва)
uniform float hide = 0.0;
uniform vec3 c_center;         // крона в мировых координатах
uniform vec3 c_ext = vec3(1.0);
uniform float ao_amt = 0.5;
uniform float leaf = 0.6;      // доля «сферической» нормали
uniform float dry = 0.0;       // 1 — выгоревшая трава
uniform vec3 tint = vec3(1.0);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	if (hide > 0.5) {
		discard;
	}
	vec4 t = texture(tex, UV);
	ALPHA = mix(1.0, t.a, cut);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 rel = (wpos - c_center) / c_ext;
	if (mode == 0) {
		float r = length(rel);
		float ao = mix(1.0 - ao_amt, 1.0, smoothstep(0.1, 1.05, r));
		ao *= mix(1.0 - ao_amt * 0.45, 1.0, smoothstep(-0.9, 0.5, rel.y));
		vec3 c = t.rgb * tint;
		float l = dot(c, vec3(0.3, 0.55, 0.15));
		c = mix(c, vec3(l) * vec3(1.42, 1.1, 0.52) * 0.95, dry);
		ALBEDO = c * ao;
	} else {
		vec3 n = normalize(NORMAL);
		if (n.z < 0.0) {
			n = -n;
		}
		vec3 s = normalize(mat3(VIEW_MATRIX) * (rel / c_ext));
		vec3 nn = normalize(mix(n, s, leaf));
		if (nn.z < 0.08) {
			nn.z = 0.08;
			nn = normalize(nn);
		}
		ALBEDO = to_lin(nn * 0.5 + 0.5);
	}
}
"""

var vp: SubViewport
var cam: Camera3D
var shader: Shader
var mats: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var gi := FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	gi.close()
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.substr(7).split(","))
	shader = Shader.new()
	shader.code = BAKE_SHADER
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(64, 64)
	get_root().add_child(vp)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 500.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	cam.environment = env
	vp.add_child(cam)
	cam.current = true
	# превью в окне
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(tr)
	await process_frame
	for job in JOBS:
		if not only.is_empty() and not only.has(job.name):
			continue
		var t0 := Time.get_ticks_msec()
		if job.kind == "grass":
			await _bake_grass()
		else:
			await _bake_model(job)
		print("BAKE %s: %.1f с" % [job.name, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


func _mat(tex: Texture2D, cut: bool, hide: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("cut", 1.0 if cut else 0.0)
	m.set_shader_parameter("hide", 1.0 if hide else 0.0)
	m.set_shader_parameter("leaf", 0.6 if cut else 0.12)
	mats.append(m)
	return m


func _set_all(param: String, v: Variant) -> void:
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter(param, v)


## Снимок вида: камера ортографическая, кадр frame (м) = [x0, y0, ширина, высота] в плоскости камеры.
func _shoot(frame: Rect2, px: Vector2i, top: bool, base: String) -> void:
	vp.size = px
	cam.size = frame.size.y
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var c := frame.get_center()
	if top:
		# сверху: вверх кадра = −Z (север)
		cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(c.x, 200.0, -c.y))
	else:
		cam.transform = Transform3D(Basis(), Vector3(c.x, c.y, 200.0))
	for pass_i in 2:
		_set_all("mode", pass_i)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(OUT + "%s_%s.png" % [base, "col" if pass_i == 0 else "nor"])


func _load_gltf(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), st)
	if err != OK:
		push_error("не загрузился " + path)
		return null
	return doc.generate_scene(st) as Node3D


func _bake_model(job: Dictionary) -> void:
	var scene := _load_gltf(SRC + "%s/%s.gltf" % [job.src, job.src])
	var spin := Node3D.new()
	vp.add_child(spin)
	var holder := Node3D.new()
	spin.add_child(holder)
	holder.add_child(scene)
	mats.clear()
	var keep: Array = []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var ok: bool = (job.nodes as Array).is_empty()
		for s in job.nodes:
			if String(mi.name).contains(s):
				ok = true
		if ok:
			keep.append(mi)
		else:
			mi.visible = false
	# материалы и габариты (в координатах сцены до масштаба)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var leaf_lo := lo
	var leaf_hi := hi
	var pts_all: Array = []  # [PackedVector3Array, is_leaf]
	for mi in keep:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for si in mesh.get_surface_count():
			var src_m := mesh.surface_get_material(si) as BaseMaterial3D
			var mname := src_m.resource_name if src_m else ""
			var hide := false
			for h in job.hide:
				if mname.contains(h):
					hide = true
			var cut := src_m != null and src_m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var tex: Texture2D = src_m.albedo_texture if src_m else null
			(mi as MeshInstance3D).set_surface_override_material(si, _mat(tex, cut, hide))
			if hide:
				continue
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var wv := PackedVector3Array()
			wv.resize(verts.size())
			for i in verts.size():
				var v: Vector3 = xf * verts[i]
				wv[i] = v
				lo = lo.min(v)
				hi = hi.max(v)
				if cut:
					leaf_lo = leaf_lo.min(v)
					leaf_hi = leaf_hi.max(v)
			pts_all.append([wv, cut])
	var h0 := hi.y - lo.y
	# у саженца ели ветки редкие: вторая копия, повёрнутая на 137°, делает крону гуще
	for d in range(1, int(job.get("dup", 1))):
		var c2 := scene.duplicate() as Node3D
		c2.rotation = Vector3(0, d * 2.4, 0)
		c2.scale = Vector3(0.97, 1.0, 0.97)
		holder.add_child(c2)
	# основание ствола: средняя точка самых нижних вершин
	var base := Vector3.ZERO
	var nb := 0
	for pa in pts_all:
		for v in (pa[0] as PackedVector3Array):
			if v.y < lo.y + h0 * 0.03:
				base += v
				nb += 1
	base /= maxf(nb, 1)
	base.y = lo.y
	var radius := 0.0
	var trunk_r := 0.0
	var ntr := 0
	for pa in pts_all:
		for v in (pa[0] as PackedVector3Array):
			var d := Vector2(v.x - base.x, v.z - base.z).length()
			radius = maxf(radius, d)
			if not pa[1] and v.y > lo.y + h0 * 0.03 and v.y < lo.y + h0 * 0.1:
				trunk_r += d
				ntr += 1
	trunk_r = trunk_r / maxf(ntr, 1)
	if leaf_lo.x > leaf_hi.x:
		leaf_lo = lo
		leaf_hi = hi
	var s: float = job.height / h0 if job.height > 0.0 else 1.0
	holder.scale = Vector3(s, s, s)
	holder.position = -base * s
	var H := h0 * s
	var R := radius * s
	var cc := (leaf_lo + leaf_hi) * 0.5
	var ce := (leaf_hi - leaf_lo) * 0.5
	# центр/размер кроны для затенения — в мировых координатах после масштаба (spin вращается!)
	_set_all("ao_amt", job.ao)
	var meta := {
		"name": job.name, "kind": job.kind, "height": H, "radius": R, "ss": SS, "cell": job.cell,
		"trunk_r": trunk_r * s, "crown_y0": (leaf_lo.y - lo.y) * s, "crown_y1": (leaf_hi.y - lo.y) * s,
		"views": [],
	}
	var yaws := [0.0, 60.0, 120.0]
	var w := 2.0 * R * 1.03
	var fh := H * 1.02
	var frame := Rect2(-w * 0.5, -0.01 * H, w, fh)
	var cpx: int = job.cell * SS
	var px := Vector2i(cpx, cpx)
	if w > fh:
		px.y = int(round(cpx * fh / w))
	else:
		px.x = int(round(cpx * w / fh))
	for yaw in yaws:
		spin.rotation = Vector3(0, -deg_to_rad(yaw), 0)
		var c_world := spin.transform * ((cc - base) * s)
		_set_all("c_center", c_world)
		_set_all("c_ext", (spin.basis.get_rotation_quaternion() * (ce * s)).abs() + Vector3(0.01, 0.01, 0.01))
		await _shoot(frame, px, false, "%s_v%d" % [job.name, int(yaw)])
		(meta.views as Array).append({"yaw": yaw, "file": "%s_v%d" % [job.name, int(yaw)], "x0": frame.position.x,
			"y0": frame.position.y, "w": frame.size.x, "h": frame.size.y, "px": [px.x, px.y]})
	if job.kind == "tree":
		spin.rotation = Vector3.ZERO
		_set_all("c_center", (cc - base) * s)
		_set_all("c_ext", ce * s + Vector3(0.01, 0.01, 0.01))
		var tf := Rect2(-w * 0.5, -w * 0.5, w, w)
		await _shoot(tf, Vector2i(cpx, cpx), true, "%s_top" % job.name)
		meta["top"] = {"file": "%s_top" % job.name, "x0": tf.position.x, "z0": tf.position.y, "w": w, "h": w, "px": [cpx, cpx],
			"y": ((cc.y - lo.y) * s)}
	var f := FileAccess.open(OUT + "%s.json" % job.name, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("  %s: высота %.1f м, радиус %.1f м, ствол r=%.2f, крона %.1f..%.1f м" % [job.name, H, R, meta.trunk_r, meta.crown_y0, meta.crown_y1])
	spin.queue_free()
	await process_frame


# ---------------------------------------------------------------- трава

## Кадры атласа травы: 2 столбца x 4 строки, кадр 1.0 x 0.5 м (основание внизу, центр по X).
## Строка = вариант (выбирается альфой цвета экземпляра MultiMesh), столбцы — разные карточки пучка.
const GRASS_FRAMES := [
	# [столбец, строка, рецепт]
	[0, 0, "green"], [1, 0, "green_seed"],
	[0, 1, "dry"], [1, 1, "dry_seed"],
	[0, 2, "mixed"], [1, 2, "clumps"],
	[0, 3, "flowers"], [1, 3, "short"],
]
const GW := 1.0
const GH := 0.5
const GPX := 512


func _blade_tex(name: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + "acg/%s.png" % name))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _bake_grass() -> void:
	var bl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC + "acg/blades.json"))
	var texs := {}
	var rects := {}
	for k in bl:
		texs[k] = _blade_tex(k)
		var good: Array = []
		for r in bl[k]:
			var rw: float = r[2] - r[0]
			var rh: float = r[3] - r[1]
			var need := 1.5 if k == "Foliage007" else 2.5
			if rh / maxf(rw, 0.001) >= need:
				good.append(r)
		rects[k] = good
	var meta := {"name": "grass", "kind": "grass", "ss": SS + 1, "frames": [], "w": GW, "h": GH, "cell": [GPX, GPX / 2]}
	for fr in GRASS_FRAMES:
		mats.clear()
		var root := Node3D.new()
		vp.add_child(root)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(fr[2])
		match fr[2]:
			"green":
				_tuft(root, rng, texs, rects, {"Foliage004": 45, "Foliage001": 30, "Foliage006": 12}, 0.18, 0.46, 0.22, 0.3)
			"green_seed":
				_tuft(root, rng, texs, rects, {"Foliage004": 35, "Foliage001": 22, "Foliage006": 8, "Foliage002": 6}, 0.2, 0.48, 0.3, 0.32)
			"dry":
				_tuft(root, rng, texs, rects, {"Foliage004": 50, "Foliage001": 30, "Foliage006": 8}, 0.18, 0.42, 0.9, 0.32)
			"dry_seed":
				_tuft(root, rng, texs, rects, {"Foliage004": 30, "Foliage006": 20, "Foliage002": 8}, 0.22, 0.48, 0.85, 0.32)
			"mixed":
				_tuft(root, rng, texs, rects, {"Foliage001": 28, "Foliage004": 40, "Foliage006": 8}, 0.18, 0.44, -1.0, 0.32)
			"clumps":
				await _clumps(root)
			"flowers":
				_tuft(root, rng, texs, rects, {"Foliage004": 30, "Foliage001": 20, "Foliage006": 6}, 0.14, 0.34, 0.2, 0.32)
				await _flowers(root, rng)
			"short":
				_tuft(root, rng, texs, rects, {"Foliage007": 22, "Foliage004": 25, "Foliage001": 10}, 0.1, 0.26, 0.2, 0.34)
		_set_all("ao_amt", 0.45)
		_set_all("c_center", Vector3(0, -0.15, 0))
		_set_all("c_ext", Vector3(0.45, 0.6, 0.45))
		for m in mats:
			(m as ShaderMaterial).set_shader_parameter("leaf", 0.65)
		var file := "grass_%s" % fr[2]
		await _shoot(Rect2(-GW * 0.5, -0.005, GW, GH), Vector2i(GPX * (SS + 1), GPX * (SS + 1) / 2), false, file)
		(meta.frames as Array).append({"col": fr[0], "row": fr[1], "file": file})
		root.queue_free()
		await process_frame
	var f := FileAccess.open(OUT + "grass.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()


## Пучок из изогнутых травинок: counts — сколько травинок из какого атласа, dry < 0 — каждой случайно.
func _tuft(root: Node3D, rng: RandomNumberGenerator, texs: Dictionary, rects: Dictionary, counts: Dictionary,
		hmin: float, hmax: float, dry: float, spread: float) -> void:
	for k in counts:
		var rs: Array = rects[k]
		if rs.is_empty():
			continue
		# отдельный материал на «сухость», чтобы смешанный пучок был пёстрым
		var groups := {}
		for i in int(counts[k]):
			var d := dry if dry >= 0.0 else (1.0 if rng.randf() < 0.45 else 0.0)
			d = clampf(d + rng.randf_range(-0.15, 0.1), 0.0, 1.0) if d > 0.0 else d
			var key := snappedf(d, 0.25)
			if not groups.has(key):
				var st0 := SurfaceTool.new()
				st0.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = st0
			var r: Array = rs[rng.randi() % rs.size()]
			var h := rng.randf_range(hmin, hmax) * (1.25 if k == "Foliage002" else 1.0)
			_blade(groups[key], rng, r, h, spread)
		for key in groups:
			var mi := MeshInstance3D.new()
			mi.mesh = (groups[key] as SurfaceTool).commit()
			var m := _mat(texs[k], true, false)
			m.set_shader_parameter("dry", float(key))
			mi.material_override = m
			root.add_child(mi)


func _blade(st: SurfaceTool, rng: RandomNumberGenerator, r: Array, h: float, spread: float) -> void:
	var rw: float = r[2] - r[0]
	var rh: float = r[3] - r[1]
	var w := h * rw / rh * rng.randf_range(0.9, 1.3)
	var ang := rng.randf() * TAU
	var dirv := Vector3(cos(ang), 0, sin(ang))
	var side := Vector3(-dirv.z, 0, dirv.x)
	var p0 := dirv * rng.randf_range(0.0, spread) * rng.randf()
	var lean := rng.randf_range(0.08, 0.75)
	var bend := rng.randf_range(0.0, 0.5)
	var seg := 5
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in seg + 1:
		var t := float(i) / seg
		var c := p0 + dirv * (lean * t + bend * t * t) * h + Vector3(0, h * t * (1.0 - 0.35 * bend * t * t), 0)
		var hw := w * 0.5
		var l := c - side * hw
		var rr := c + side * hw
		if i > 0:
			var v0 := 1.0 - (t - 1.0 / seg)
			var v1 := 1.0 - t
			var uv := func(u: float, v: float) -> Vector2: return Vector2(lerpf(r[0], r[2], u), lerpf(r[1], r[3], v))
			var n := side.cross(c - prev_l).normalized()
			for q in [[prev_l, 0.0, v0], [prev_r, 1.0, v0], [rr, 1.0, v1], [prev_l, 0.0, v0], [rr, 1.0, v1], [l, 0.0, v1]]:
				st.set_normal(n)
				st.set_uv(uv.call(q[1], q[2]))
				st.add_vertex(q[0])
		prev_l = l
		prev_r = rr


## Кадр из настоящих пучков grass_medium_02 (5 штук разного размера рядом).
func _clumps(root: Node3D) -> void:
	var sc := _load_gltf(SRC + "grass_medium_02/grass_medium_02.gltf")
	root.add_child(sc)
	var xs := {"_a": -0.36, "_b": 0.3, "_c": -0.12, "_d": 0.12, "_e": 0.0}
	for n in sc.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for k in xs:
			if String(mi.name).ends_with(k):
				var aabb := mi.get_aabb()
				mi.position = Vector3(xs[k] - aabb.get_center().x * 1.3, 0, -aabb.get_center().z * 1.3)
				mi.scale = Vector3(1.3, 1.3, 1.3)
		for si in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(si) as BaseMaterial3D
			mi.set_surface_override_material(si, _mat(sm.albedo_texture if sm else null, true, false))
	await process_frame


## Цветы ursinia (жёлто-оранжевые ромашки) среди травы.
func _flowers(root: Node3D, rng: RandomNumberGenerator) -> void:
	var sc := _load_gltf(SRC + "flower_ursinia/flower_ursinia.gltf")
	root.add_child(sc)
	var i := 0
	for n in sc.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var aabb := mi.get_aabb()
		var s := 1.6
		mi.scale = Vector3(s, s, s)
		mi.position = Vector3(-0.3 + i * 0.15 - aabb.get_center().x * s, 0, rng.randf_range(-0.1, 0.1) - aabb.get_center().z * s)
		for si in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(si) as BaseMaterial3D
			mi.set_surface_override_material(si, _mat(sm.albedo_texture if sm else null, true, false))
		i += 1
	await process_frame
