extends Node3D
## Предпросмотр зданий Bld: ровная площадка, солнце и небо как в игре, ряд всех типов.
## Снимает ракурсы снаружи/изнутри в user://bld_*.png, печатает треугольники и вызовы отрисовки, выходит.
## Запуск: godot --path . --rendering-method gl_compatibility --resolution 960x540 --position 20,40 res://scenes/bld_preview.tscn
## Аргументы после «--»: --seed=N, --only=тип[,тип], --village (снимок «посёлка» из случайных домов), --noshots.

const SPACING := 30.0
var items: Array = []   # [kind, node_root, info, out]
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Geo.ground_fn = func(_x: float, _z: float) -> float: return 0.0
	_environment()
	_ground()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.get("seed", "7"))
	var kinds: Array = Bld.TYPES.duplicate()
	if args.has("only"):
		kinds = Array(String(args.only).split(","))
	if args.has("village"):
		_village(rng)
	else:
		var x := 0.0
		for k in kinds:
			var root := Node3D.new()
			root.name = k
			add_child(root)
			var g := Geo.new()
			var out := {}
			var t0 := Time.get_ticks_usec()
			var info: Dictionary = Bld.build(k, g, rng, Vector3(x, 0, 0), 0.0, out)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var mi := g.finish(root, k)
			var tris := 0
			var mats: Array = []
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_len(s) / 3
				var m := mi.mesh.surface_get_material(s)
				mats.append(_mat_name(m))
			var shapes := 0
			for kk in g.shapes:
				shapes += (g.shapes[kk] as Array).size()
			var pts := []
			for key in out:
				pts.append("%s:%d" % [key, (out[key] as Array).size()])
			print("BLD %-11s tris=%5d mats=%2d shapes=%3d build=%.1fms  %s  pts[%s]" % [k, tris, mats.size(), shapes, ms, ", ".join(mats), " ".join(pts)])
			items.append([k, root, info, out])
			x += SPACING
	if args.has("noshots"):
		get_tree().quit()
		return
	await _shots()
	get_tree().quit()


func _mat_name(m: Material) -> String:
	for k in Mats._cache:
		if Mats._cache[k] == m:
			return String(k)
	return "?"


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/sky/sky_2k.hdr")
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.9
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.66, 0.62, 0.56)
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.fog_enabled = true
	env.fog_light_color = Color(0.69, 0.73, 0.81)
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.12
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.09
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	sun.look_at_from_position(Vector3(-0.377, 0.741, 0.556) * 100.0, Vector3.ZERO, Vector3.UP)


func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(600, 300)
	mi.mesh = pmesh
	var m := ORMMaterial3D.new()
	m.albedo_texture = load("res://assets/tex/sandy_gravel_02_diff.jpg")
	m.orm_texture = load("res://assets/tex/sandy_gravel_02_arm.jpg")
	m.normal_texture = load("res://assets/tex/sandy_gravel_02_nor.jpg")
	m.normal_enabled = true
	m.uv1_scale = Vector3(150, 75, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.position = Vector3(180, 0, 0)
	add_child(mi)


## «Посёлок»: случайные дома вдоль улицы — проверка разнообразия и вызовов отрисовки на весь Geo.
func _village(rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	add_child(root)
	var g := Geo.new()
	var kinds := ["house_fence", "house", "house2", "house_east", "shed", "house_fence", "house2", "ruin", "shop", "garages", "block", "house"]
	var out := {}
	for i in kinds.size():
		var side := 1.0 if i % 2 == 0 else -1.0
		var x := floorf(i / 2.0) * 22.0
		var yaw := 0.0 if side > 0 else PI
		Bld.build(kinds[i], g, rng, Vector3(x, 0, -side * 14.0), yaw, out)
	var mi := g.finish(root, "village")
	var tris := 0
	for s in mi.mesh.get_surface_count():
		tris += mi.mesh.surface_get_array_len(s) / 3
	print("VILLAGE tris=%d mats=%d" % [tris, mi.mesh.get_surface_count()])
	items.append(["village", root, {"pos": Vector3(55, 0, 0), "w": 120.0, "d": 40.0, "floor_y": 0.4, "top_y": 12.0}, out])


func _cam() -> Camera3D:
	var cam := get_node_or_null("cam") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = "cam"
		cam.fov = 70.0
		cam.near = 0.05
		add_child(cam)
		cam.current = true
	return cam


func _shot(name: String, from: Vector3, to: Vector3) -> void:
	var cam := _cam()
	cam.look_at_from_position(from, to, Vector3.UP)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var pr := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	get_viewport().get_texture().get_image().save_png("user://bld_%s.png" % name)
	print("SHOT %-22s draw=%d prim=%d" % [name, dc, pr])


func _shots() -> void:
	if args.has("village"):
		var it: Array = items[0]
		await _shot("village_street", Vector3(-8, 2.0, 2), Vector3(30, 3.0, 0))
		await _shot("village_air", Vector3(-25, 35, 45), Vector3(50, 0, 0))
		await _shot("village_back", Vector3(125, 4.0, -3), Vector3(70, 3.0, 0))
		return
	var cam := _cam()
	for it in items:
		var kind: String = it[0]
		var root: Node3D = it[1]
		var info: Dictionary = it[2]
		var out: Dictionary = it[3]
		for o in items:
			(o[1] as Node3D).visible = o[1] == root
		var p: Vector3 = info.pos
		var w: float = info.w
		var d: float = info.d
		var fy: float = info.floor_y
		var top: float = info.top_y
		var r := maxf(w, d)
		await _shot(kind + "_front", p + Vector3(-w * 0.55, 1.7 + top * 0.15, d * 0.5 + r * 0.9), p + Vector3(0, top * 0.45, 0))
		await _shot(kind + "_back", p + Vector3(w * 0.7, 2.5 + top * 0.3, -d * 0.5 - r * 0.8), p + Vector3(0, top * 0.4, 0))
		var inside: Array = out.get("inside", [])
		var ip: Vector3 = inside[0] if inside.size() > 0 else p + Vector3(0, fy, 0)
		var look := p + Vector3(w * 0.45, fy + 1.2, d * 0.45)
		match kind:
			"block":
				await _shot(kind + "_stair", p + Vector3(0.0, fy + 1.7, d * 0.5 - 0.5), p + Vector3(0, fy + 2.6, -2.5))
				look = ip + Vector3(-3, 1.0, 2)
			"hq":
				await _shot(kind + "_lobby", p + Vector3(1.2, fy + 1.7, d * 0.5 - 0.6), p + Vector3(0, fy + 2.4, -2.0))
			"house2":
				await _shot(kind + "_stair", p + Vector3(-w * 0.5 + 2.0, fy + 1.7, d * 0.5 - 0.6), p + Vector3(-w * 0.5 + 0.9, fy + 2.4, -1.0))
			"warehouse":
				look = p + Vector3(-w * 0.4, fy + 2.5, -d * 0.4)
				ip = p + Vector3(w * 0.15, fy, d * 0.2)
		await _shot(kind + "_in", ip + Vector3(0, 1.6, 0) - (look - ip).normalized() * 0.8, look)
	for o in items:
		(o[1] as Node3D).visible = true
	var mid := (items.size() - 1) * SPACING * 0.5
	await _shot("all_air", Vector3(mid, 60, 70), Vector3(mid, 0, 0))
	await _shot("all_street", Vector3(-12, 1.8, 18), Vector3(40, 3, 0))
