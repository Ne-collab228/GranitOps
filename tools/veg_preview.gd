extends Node3D
## Витрина растительности (scenes/veg_preview.tscn): площадка, солнце и небо как в игре, ряды всех видов,
## лес вдали (ближний/дальний LOD) и поле травы MultiMesh. Снимает ракурсы в user://veg_*.png
## (%APPDATA%\GranitOps), печатает вызовы отрисовки/треугольники и выходит.
## G --path . --rendering-method gl_compatibility --resolution 960x540 --position 20,40 res://scenes/veg_preview.tscn
##   [-- --nowind --nonormal --stay]

const SUN := Vector3(-0.377, 0.741, 0.556)
const ROW_Z := -30.0

var rng := RandomNumberGenerator.new()
var cam: Camera3D


func _ready() -> void:
	rng.seed = 12345
	var args := OS.get_cmdline_user_args()
	Veg.set_wind(not args.has("--nowind"))
	Veg.set_normals(not args.has("--nonormal"))
	_env()
	_ground()
	_rows()
	_forest()
	_grass_field()
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 1200.0
	add_child(cam)
	cam.current = true
	if not args.has("--stay"):
		_shots()


func _env() -> void:
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
	env.fog_sky_affect = 0.0
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
	sun.look_at_from_position(SUN * 100.0, Vector3.ZERO, Vector3.UP)


func _ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/tex/dry_ground_rocks_diff.jpg")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/tex/dry_ground_rocks_nor.jpg")
	m.uv1_scale = Vector3(400, 400, 400)
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	add_child(mi)


func _tint(k: float) -> Color:
	var v := rng.randf_range(1.0 - k, 1.0 + k * 0.6)
	return Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.9, 1.04))


## Ряды: кусты на 12–16 м, деревья (ближний LOD) на 30 м.
func _rows() -> void:
	var x := -10.0
	for k in Veg.SHRUBS:
		var info := Veg.shrub(k)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, 0, -13.0))
		var xf2 := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.8), Vector3(x + 1.6, 0, -16.0))
		var mmi := Veg.multimesh(info, [xf, xf2], [_tint(0.1), _tint(0.1)])
		add_child(mmi)
		x += 5.0
	x = -27.0
	for k in Veg.TREES:
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, 0, ROW_Z))
		for lod in 2:
			add_child(Veg.multimesh(Veg.tree(k, lod), [xf], [_tint(0.08)]))
		x += 18.0


## Лес вдали: куски 60 м, на каждый — ближний и дальний LOD с теми же преобразованиями.
func _forest() -> void:
	for cz in range(-6, -1):
		for cx in range(-4, 4):
			var by_kind := {}
			for i in 14:
				var k: String = ["broadleaf", "broadleaf", "fir", "fir", "searsia", "dead"][rng.randi() % 6]
				var p := Vector3((cx + rng.randf()) * 60.0, 0, (cz + rng.randf()) * 60.0 - 20.0)
				var s := rng.randf_range(0.75, 1.2)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s)), p)
				if not by_kind.has(k):
					by_kind[k] = [[], []]
				by_kind[k][0].append(xf)
				by_kind[k][1].append(_tint(0.1))
			for k in by_kind:
				for lod in 2:
					add_child(Veg.multimesh(Veg.tree(k, lod), by_kind[k][0], by_kind[k][1]))


## Поле травы радиусом 50 м, куски 25 м; варианты по шуму (зелёные/сухие пятна).
func _grass_field() -> void:
	var info := Veg.grass()
	var nz := FastNoiseLite.new()
	nz.frequency = 0.04
	var n := 0
	for cz in range(-2, 2):
		for cx in range(-2, 2):
			var xfs: Array = []
			var cols: Array = []
			for i in 650:
				var p := Vector3((cx + rng.randf()) * 25.0, 0, (cz + rng.randf()) * 25.0)
				if Vector2(p.x, p.z).length() > 50.0:
					continue
				var s := rng.randf_range(0.5, 1.35)
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s)), p))
				var f := nz.get_noise_2d(p.x, p.z)
				var v := 0 if f > 0.25 else (1 if f < -0.2 else 2)
				if rng.randf() < 0.07:
					v = 3
				cols.append(Veg.inst_color(_tint(0.12), v))
			n += xfs.size()
			if not xfs.is_empty():
				add_child(Veg.multimesh(info, xfs, cols))
	print("VEG трава: ", n, " пучков")


func _shots() -> void:
	var t := Vector3(-27.0 + 18.0 * 0, 0, ROW_Z)  # первое дерево (лиственное)
	var sd := Vector3(SUN.x, 0, SUN.z).normalized()
	var views := [
		["near", Vector3(0, 1.7, 2), Vector3(0, 1.2, -14)],
		["30m", Vector3(-3, 1.7, 0), Vector3(-3, 5, ROW_Z)],
		["under", Vector3(-24, 1.7, -25), Vector3(-27, 7.5, ROW_Z)],
		["fir", Vector3(-1, 1.7, -18), Vector3(9, 5, ROW_Z)],
		["150m", Vector3(0, 14, 150), Vector3(0, 4, -80)],
		["backlit", t - sd * 22.0 + Vector3(0, 1.7, 0), t + Vector3(0, 5, 0)],
		["grass", Vector3(6, 1.2, 10), Vector3(6, 0, 0)],
	]
	for i in 20:
		await get_tree().process_frame
	for v in views:
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		get_viewport().get_texture().get_image().save_png("user://veg_%s.png" % v[0])
		print("VEG %-8s draw %d  prim %d" % [v[0], dc, pr])
	# ветер: тот же кадр через 0.7 с (сравнить veg_grass.png и veg_grass_b.png)
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://veg_grass_b.png")
	# база без растительности (небо + земля) — для оценки цены растительности
	for c in get_children():
		if c is MultiMeshInstance3D:
			(c as MultiMeshInstance3D).visible = false
	cam.look_at_from_position(views[0][1], views[0][2], Vector3.UP)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("VEG без растительности: draw %d  prim %d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	for k in Veg.TREES:
		print("VEG дерево %-10s ближний %d тр., дальний %d тр." % [k, Veg.tree(k, 0).tris, Veg.tree(k, 1).tris])
	for k in Veg.SHRUBS:
		print("VEG куст %-10s %d тр., высота %.1f м" % [k, Veg.shrub(k).tris, Veg.shrub(k).height])
	print("VEG трава %d тр." % Veg.grass().tris)
	get_tree().quit()
