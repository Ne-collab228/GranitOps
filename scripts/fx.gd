class_name Fx
extends Node3D
## Эффекты: попадания, декали, вспышки, взрывы, огонь, дым. Всё на пулах.

var _pools := {}
var _decals: Array[MeshInstance3D] = []
var _decal_i := 0
var _decal_mats := {}
var _flashes: Array[MeshInstance3D] = []
var _flash_off: Array[float] = []
var _flash_i := 0
var _light: OmniLight3D
var _light_t := 0.0
var _time := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var dust := Color(0.74, 0.65, 0.5, 0.75)
	_make("dirt", 5, {"tex": "smoke", "amount": 9, "life": 0.9, "spread": 32.0, "v": [2.0, 6.0], "g": -4.0, "size": [0.2, 0.55], "col": dust, "grow": 2.4})
	_make("concrete", 5, {"tex": "smoke", "amount": 9, "life": 0.8, "spread": 38.0, "v": [2.0, 6.5], "g": -4.0, "size": [0.18, 0.5], "col": Color(0.78, 0.77, 0.74, 0.7), "grow": 2.4})
	_make("metal", 5, {"tex": "spark", "amount": 9, "life": 0.32, "spread": 45.0, "v": [5.0, 13.0], "g": -9.8, "size": [0.04, 0.09], "col": Color(1.0, 0.8, 0.4, 1.0), "add": true, "grow": 0.3})
	_make("wood", 4, {"tex": "smoke2", "amount": 8, "life": 0.6, "spread": 40.0, "v": [2.0, 5.0], "g": -6.0, "size": [0.1, 0.3], "col": Color(0.7, 0.58, 0.4, 0.75), "grow": 1.8})
	_make("body", 5, {"tex": "smoke2", "amount": 7, "life": 0.45, "spread": 28.0, "v": [1.5, 4.5], "g": -7.0, "size": [0.08, 0.22], "col": Color(0.42, 0.02, 0.02, 0.9), "grow": 1.6})
	_make("fireball", 3, {"tex": "smoke", "amount": 14, "life": 0.55, "spread": 180.0, "v": [3.0, 9.0], "g": 2.0, "size": [1.6, 3.4], "col": Color(1.0, 0.62, 0.22, 1.0), "add": true, "grow": 1.6})
	_make("blast_smoke", 3, {"tex": "smoke", "amount": 14, "life": 3.2, "spread": 180.0, "v": [1.5, 5.0], "g": 1.2, "size": [2.2, 4.8], "col": Color(0.16, 0.15, 0.14, 0.75), "grow": 1.8, "damp": 1.5})
	_make("debris", 3, {"tex": "spark", "amount": 22, "life": 1.1, "spread": 75.0, "v": [8.0, 22.0], "g": -9.8, "size": [0.06, 0.14], "col": Color(1.0, 0.7, 0.3, 1.0), "add": true, "grow": 0.3})
	_make("puff", 4, {"tex": "smoke", "amount": 3, "life": 0.7, "spread": 25.0, "v": [0.6, 1.6], "g": 0.6, "size": [0.12, 0.3], "col": Color(0.7, 0.7, 0.7, 0.28), "grow": 2.6})

	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	for key in ["concrete", "metal", "wood"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/gen/hole_%s.png" % key)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.9
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_decal_mats[key] = m
	for i in 40:
		var d := MeshInstance3D.new()
		d.mesh = quad
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		d.visibility_range_end = 35.0
		add_child(d)
		_decals.append(d)

	var fq := QuadMesh.new()
	fq.size = Vector2(0.55, 0.55)
	for i in 6:
		var f := MeshInstance3D.new()
		f.mesh = fq
		var fm := Mats.sprite("muzzle", true, true).duplicate() as StandardMaterial3D
		fm.uv1_scale = Vector3(0.5, 0.5, 1.0)
		fm.uv1_offset = Vector3((i % 2) * 0.5, ((i / 2) % 2) * 0.5, 0.0)
		f.material_override = fm
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		add_child(f)
		_flashes.append(f)
		_flash_off.append(0.0)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.45)
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


func _make(key: String, count: int, c: Dictionary) -> void:
	var mat := Mats.sprite(c.tex, c.get("add", false), false, true)
	var quad := QuadMesh.new()
	quad.material = mat
	var col: Color = c.col
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	if c.get("add", false) and key == "fireball":
		grad.add_point(0.5, Color(0.7, 0.2, 0.05, 0.6))
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0 / maxf(1.0, float(c.grow))))
	curve.add_point(Vector2(1.0, 1.0))
	if float(c.grow) < 1.0:
		curve = Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, float(c.grow)))
	var arr: Array = []
	for i in count:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.94
		p.amount = int(c.amount)
		p.lifetime = float(c.life)
		p.mesh = quad
		p.spread = float(c.spread)
		p.initial_velocity_min = c.v[0]
		p.initial_velocity_max = c.v[1]
		p.gravity = Vector3(0, float(c.g), 0)
		p.scale_amount_min = c.size[0]
		p.scale_amount_max = c.size[1]
		p.scale_amount_curve = curve
		p.color_ramp = grad
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.damping_min = float(c.get("damp", 0.0))
		p.damping_max = float(c.get("damp", 0.0))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		arr.append(p)
	_pools[key] = [arr, 0]


func emit(key: String, pos: Vector3, dir := Vector3.UP) -> void:
	var pool: Array = _pools.get(key, [])
	if pool.is_empty():
		return
	var arr: Array = pool[0]
	var p: CPUParticles3D = arr[pool[1]]
	pool[1] = (int(pool[1]) + 1) % arr.size()
	p.global_position = pos
	p.direction = dir
	p.restart()
	p.emitting = true


func impact(pos: Vector3, normal: Vector3, surf: String, dir: Vector3) -> void:
	var key := surf
	if surf == "sheet":
		key = "metal"
	if not _pools.has(key):
		key = "concrete"
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(pos) if cam else 0.0
	if dist < 260.0:
		emit(key, pos + normal * 0.03, (normal - dir * 0.35).normalized())
	if surf != "body" and surf != "dirt" and dist < 70.0:
		var dk := "metal" if key == "metal" else ("wood" if key == "wood" else "concrete")
		var d := _decals[_decal_i]
		_decal_i = (_decal_i + 1) % _decals.size()
		d.material_override = _decal_mats[dk]
		var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
		var b := Basis.looking_at(-normal, up).rotated(normal, randf() * TAU)
		var s := randf_range(0.8, 1.4)
		d.global_transform = Transform3D(b.scaled(Vector3(s, s, s)), pos + normal * (0.008 + _decal_i * 0.0002))
		d.visible = true
	if dist < 90.0:
		Sfx.play_at("hit_" + ("metal" if key == "metal" else key), pos, -6.0, randf_range(0.9, 1.15), 5.0, 90.0, dist / 343.0)


## Дульная вспышка в мире (для противников).
func flash(pos: Vector3) -> void:
	var f := _flashes[_flash_i]
	_flash_off[_flash_i] = _time + 0.05
	_flash_i = (_flash_i + 1) % _flashes.size()
	f.global_position = pos
	var s := randf_range(0.7, 1.2)
	f.scale = Vector3(s, s, s)
	f.visible = true


func light(pos: Vector3, energy: float, rng: float, time: float) -> void:
	if int(Settings.data.quality) < 1:
		return
	_light.global_position = pos
	_light.light_energy = energy
	_light.omni_range = rng
	_light.visible = true
	_light_t = _time + time


func _process(delta: float) -> void:
	_time += delta
	for i in _flashes.size():
		if _flashes[i].visible and _time > _flash_off[i]:
			_flashes[i].visible = false
	if _light.visible and _time > _light_t:
		_light.visible = false


func explosion(pos: Vector3, radius := 9.0, dmg := 170.0) -> void:
	emit("fireball", pos + Vector3(0, 0.6, 0), Vector3.UP)
	emit("blast_smoke", pos + Vector3(0, 0.8, 0), Vector3.UP)
	emit("debris", pos + Vector3(0, 0.3, 0), Vector3.UP)
	emit("dirt", pos + Vector3(0, 0.2, 0), Vector3.UP)
	light(pos + Vector3(0, 1.2, 0), 8.0, radius * 2.5, 0.12)
	var pl: Player = Game.player
	var listener: Vector3 = pl.global_position if pl else pos
	var dist := listener.distance_to(pos)
	Sfx.play_at("explosion_far" if dist > 160.0 else "explosion", pos, 6.0, randf_range(0.92, 1.05), 70.0, 2000.0, dist / 343.0)
	Game.noise(pos, 260.0)
	var space := get_world_3d().direct_space_state
	for e in Game.enemies:
		if is_instance_valid(e) and e.alive():
			var c: Vector3 = e.global_position + Vector3(0, 1.0, 0)
			var d := c.distance_to(pos)
			if d < radius:
				var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), c, Game.L_WORLD)
				if space.intersect_ray(q).is_empty():
					if e.take_blast(dmg * (1.0 - d / radius) + 20.0, pos) and pl:
						pl.on_hit_enemy({"zone": "body", "killed": true}, 0.0)
	for v in Game.vehicles:
		if is_instance_valid(v) and not v.dead:
			var dv := v.global_position.distance_to(pos)
			if dv < radius + 2.5:
				v.take_blast(dmg * (1.0 - dv / (radius + 2.5)), pos)
	if pl and not pl.dead and pl.vehicle == null:
		if dist < radius:
			var q2 := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pl.aim_point(), Game.L_WORLD)
			if space.intersect_ray(q2).is_empty():
				pl.take_damage(dmg * (1.0 - dist / radius), pos)
				Sfx.play("ring", -6.0)
		pl.shake(clampf(1.6 - dist / 45.0, 0.0, 1.4))


## Постоянный огонь с дымом (горящая цель).
func fire(pos: Vector3, size := 1.0) -> void:
	var fl := _continuous("smoke", true, 12, 0.9, Color(1.0, 0.55, 0.15, 0.9), [0.9 * size, 1.9 * size], [1.5, 3.2], 0.6)
	fl.position = pos
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fl.emission_box_extents = Vector3(1.2, 0.2, 1.2) * size
	var sm := _continuous("smoke", false, 16, 5.5, Color(0.12, 0.11, 0.1, 0.7), [2.0 * size, 4.5 * size], [2.5, 4.5], 2.2)
	sm.position = pos + Vector3(0, 1.5, 0)
	sm.gravity = Vector3(1.2, 0.8, 0.4)
	var pl := AudioStreamPlayer3D.new()
	pl.stream = Sfx.streams.get("fire")
	pl.unit_size = 9.0
	pl.max_distance = 90.0
	pl.position = pos
	add_child(pl)
	pl.play()


func smoke_marker(pos: Vector3, color: Color) -> void:
	var sm := _continuous("smoke", false, 14, 5.0, color, [0.8, 2.6], [1.6, 2.6], 3.0)
	sm.position = pos
	sm.gravity = Vector3(0.9, 0.5, 0.3)


func _continuous(tex: String, additive: bool, amount: int, life: float, col: Color, size: Array, vel: Array, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.material = Mats.sprite(tex, additive, false, true)
	p.mesh = quad
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 14.0
	p.initial_velocity_min = vel[0]
	p.initial_velocity_max = vel[1]
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = size[0]
	p.scale_amount_max = size[1]
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0 / maxf(1.0, grow)))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	grad.add_point(0.15, col)
	grad.set_color(grad.get_point_count() - 1, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.0))
	p.color_ramp = grad
	p.angle_max = 360.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 40, 40))
	add_child(p)
	return p
