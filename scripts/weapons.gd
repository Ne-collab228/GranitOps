class_name Weapons
extends Node3D
## Оружие игрока: стрельба, отдача, разброс, перезарядка, анимация модели от первого лица.

var defs: Array = []
var ids: Array = []

var player: Player
var models: Array = []
var ammo: Array[int] = []
var reserve: Array[int] = []
var semi: Array[bool] = []
var cur := 0
var grenades := 3
var medkits := 3

var ads := 0.0
var cool := 0.0
var reload_t := 0.0
var reload_total := 1.0
var reload_stage := 0
var reload_empty := false
var switch_t := 0.0
var switch_to := -1
var bolt_t := 0.0
var bolt_snd := false
var heal_t := 0.0
var heat := 0.0
var kick := 0.0
var slide := 0.0
var sway := Vector2.ZERO
var bob_t := 0.0
var sprint_blend := 0.0
var fired_t := 99.0
var shot_i := 0
var time := 0.0
var scoped := false

var flash: MeshInstance3D
var flash_mat: StandardMaterial3D
var flash_t := 0.0


func setup(p: Player) -> void:
	player = p
	var lo := Arsenal.loadout()
	ids = lo.slots
	for i in ids.size():
		var id: String = ids[i]
		var att: Dictionary = lo.att[id]
		defs.append(Arsenal.effective(id, att))
		var m := GunModels.build(id, att)
		models.append(m)
		var root: Node3D = m.root
		add_child(root)
		root.visible = i == cur
		root.position = m.hip
		ammo.append(int(defs[i].mag))
		reserve.append(int(defs[i].reserve))
		semi.append(false)
	flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.2)
	flash.mesh = q
	flash_mat = Mats.sprite("muzzle", true, false).duplicate() as StandardMaterial3D
	flash_mat.uv1_scale = Vector3(0.5, 0.5, 1.0)
	flash_mat.use_fov_override = true
	flash_mat.fov_override = 52.0
	flash_mat.use_z_clip_scale = true
	flash_mat.z_clip_scale = 0.35
	flash.material_override = flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	add_child(flash)


func def() -> Dictionary:
	return defs[cur]


func busy() -> bool:
	return reload_t > 0.0 or switch_t > 0.0 or heal_t > 0.0


func is_semi() -> bool:
	return semi[cur] or not bool(def().auto)


func refill() -> void:
	for i in defs.size():
		reserve[i] = int(defs[i].reserve)
	grenades = 3
	medkits = maxi(medkits, 3)


## Подобранные с противника патроны: по магазину-полтора на каждый ствол.
func add_ammo(mags := 1.0) -> void:
	for i in defs.size():
		var cap := int(float(defs[i].reserve) * 1.5)
		reserve[i] = mini(cap, reserve[i] + int(ceil(float(defs[i].mag) * mags)))


func total_ammo() -> int:
	var n := 0
	for i in defs.size():
		n += ammo[i] + reserve[i]
	return n


func spread_deg() -> float:
	var d := def()
	var s := lerpf(float(d.hip), float(d.ads), ads)
	var sp := Vector2(player.velocity.x, player.velocity.z).length()
	s += sp * lerpf(0.55, 0.12, ads)
	if not player.is_on_floor():
		s += 3.0
	if player.crouching:
		s *= 0.8
	s += minf(heat, 8.0) * lerpf(0.22, 0.05, ads)
	s += player.suppression * 1.2
	return s


func muzzle_world() -> Vector3:
	var root: Node3D = models[cur].root
	return root.global_transform * (models[cur].muzzle as Vector3)


# ------------------------------------------------------------------ действия
func start_reload() -> void:
	var d := def()
	if busy() or bolt_t > 0.0 or ammo[cur] >= int(d.mag) or reserve[cur] <= 0:
		return
	reload_empty = ammo[cur] == 0
	reload_total = float(d.reload) * (1.2 if reload_empty else 1.0)
	reload_t = reload_total
	reload_stage = 0


func switch_weapon(i: int) -> void:
	i = posmod(i, defs.size())
	if i == cur or switch_t > 0.0 or heal_t > 0.0:
		return
	reload_t = 0.0
	bolt_t = 0.0
	switch_to = i
	switch_t = 0.45
	Sfx.play("cloth", -8.0)


func toggle_mode() -> void:
	if bool(def().auto):
		semi[cur] = not semi[cur]
		Sfx.play("dry", -10.0, 1.3)


func throw_grenade() -> void:
	Blackbox.event("граната")
	if grenades <= 0 or busy():
		return
	grenades -= 1
	Sfx.play("pin", -4.0)
	var g := Grenade.new()
	var cam := player.cam
	var fwd := -cam.global_transform.basis.z
	g.position = cam.global_position + fwd * 0.5 + cam.global_transform.basis.x * 0.2 - Vector3(0, 0.15, 0)
	g.linear_velocity = fwd * 17.0 + Vector3(0, 3.5, 0) + player.velocity * 0.6
	g.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	Game.fx.get_parent().add_child(g)
	switch_t = 0.4
	switch_to = -1


func use_medkit() -> void:
	if medkits <= 0 or busy() or player.hp >= 99.0:
		return
	medkits -= 1
	heal_t = 2.2
	Sfx.play("cloth", -4.0, 0.8)


func _try_fire(pressed: bool) -> void:
	if busy() or cool > 0.0 or bolt_t > 0.0 or sprint_blend > 0.45:
		return
	if ammo[cur] <= 0:
		if pressed:
			Sfx.play("dry", -6.0)
			start_reload()
		return
	_fire()


func _fire() -> void:
	var d := def()
	ammo[cur] -= 1
	cool = 60.0 / float(d.rpm)
	fired_t = 0.0
	shot_i += 1
	Game.stats.shots += 1
	var cam := player.cam
	var b := cam.global_transform.basis
	var spread := deg_to_rad(spread_deg())
	var zero := Ballistics.GRAVITY * float(d.zero) / (2.0 * float(d.speed) * float(d.speed))
	var tr: int = int(d.tracer)
	var muzzle := muzzle_world()
	var pellets: int = int(d.pellets)
	for k in pellets:
		var ang := randf() * TAU
		var rad := sqrt(randf()) * spread
		var dir := (-b.z + b.x * cos(ang) * rad + b.y * (sin(ang) * rad + zero)).normalized()
		Game.ballistics.fire(cam.global_position, dir, float(d.speed) * (randf_range(0.93, 1.0) if pellets > 1 else 1.0), float(d.dmg), player, true,
			tr > 0 and shot_i % tr == 0 and k == 0, muzzle, float(d.drag))
	var r: Vector2 = d.recoil
	var mult := (0.8 + minf(heat, 6.0) * 0.07) * lerpf(1.0, 0.75, ads) * (0.85 if player.crouching else 1.0)
	player.add_recoil(r.x * mult, (randf_range(-r.y, r.y) + sin(heat * 1.3) * r.y * 0.5) * mult)
	heat += 1.0
	kick += float(d.kick)
	var fl: float = d.flash
	if not scoped and fl > 0.0:
		flash_t = 0.045
		flash.visible = true
		flash_mat.uv1_offset = Vector3((randi() % 2) * 0.5, (randi() % 2) * 0.5, 0.0)
		var fs := randf_range(0.8, 1.3) * fl
		flash.transform = Transform3D(Basis(Vector3.BACK, randf() * TAU).scaled(Vector3(fs, fs, fs)),
			(models[cur].root as Node3D).transform * (models[cur].muzzle as Vector3))
		Game.fx.emit("puff", muzzle - b.z * 0.1, -b.z)
	if fl > 0.0:
		Game.fx.light(muzzle, 2.2, 7.0, 0.05)
	Sfx.play(d.sound, float(d.vol), float(d.pitch) * randf_range(0.97, 1.03))
	Sfx.casing(1.0 if d.get("bolt", false) or d.get("pump", false) else 0.32)
	Game.noise(player.global_position, float(d.noise))
	if d.get("bolt", false):
		bolt_t = 1.05
		bolt_snd = false
		cool = 1.2
	elif d.get("pump", false):
		bolt_t = 0.62
		bolt_snd = false
	if d.get("slide", false):
		slide = 1.0
	if Settings.is_mobile and Settings.data.vibration:
		Input.vibrate_handheld(16)


func _apply_switch() -> void:
	if switch_to >= 0:
		(models[cur].root as Node3D).visible = false
		cur = switch_to
		(models[cur].root as Node3D).visible = true
		switch_to = -1
		ads = 0.0
		heat = 0.0


# ------------------------------------------------------------------ кадр
func update(delta: float) -> void:
	time += delta
	var d := def()
	cool = maxf(0.0, cool - delta)
	fired_t += delta
	heat = maxf(0.0, heat - delta * 5.0)
	if switch_t > 0.0:
		switch_t -= delta
		if switch_t <= 0.22:
			_apply_switch()
			d = def()
	if reload_t > 0.0:
		reload_t -= delta
		var k := 1.0 - reload_t / reload_total
		if reload_stage == 0 and k > 0.12:
			Sfx.play("mag_out", -4.0)
			reload_stage = 1
		elif reload_stage == 1 and k > 0.56:
			Sfx.play("mag_in", -4.0)
			reload_stage = 2
		elif reload_stage == 2 and k > 0.8 and reload_empty:
			Sfx.play("pistol_slide" if d.get("slide", false) else ("bolt_action" if d.get("bolt", false) or d.get("pump", false) else "bolt"), -4.0)
			reload_stage = 3
		if reload_t <= 0.0:
			var take := mini(int(d.mag) - ammo[cur], reserve[cur])
			ammo[cur] += take
			reserve[cur] -= take
	if bolt_t > 0.0:
		bolt_t -= delta
		if not bolt_snd and bolt_t < (0.5 if d.get("pump", false) else 0.85):
			bolt_snd = true
			Sfx.play("bolt_action", -5.0, 1.25 if d.get("pump", false) else 1.0)
	if heal_t > 0.0:
		heal_t -= delta
		if heal_t <= 0.0:
			player.heal(60.0)
	sprint_blend = move_toward(sprint_blend, 1.0 if (player.sprinting and reload_t <= 0.0) else 0.0, delta * 5.0)
	var want := player.in_ads and not player.sprinting and not busy()
	ads = move_toward(ads, 1.0 if want else 0.0, delta / float(d.ads_time))
	scoped = bool(d.scope) and ads > 0.82
	if player.in_fire_pressed or (player.in_fire and not is_semi()):
		_try_fire(player.in_fire_pressed)
	_animate(delta)


func _animate(delta: float) -> void:
	var m: Dictionary = models[cur]
	var root: Node3D = m.root
	var s := smoothstep(0.0, 1.0, ads)
	var pos: Vector3 = (m.hip as Vector3).lerp(m.ads, s)
	var rot := Vector3.ZERO
	var sp := Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor():
		bob_t += delta * sp * 1.9
	var bob := clampf(sp / 4.5, 0.0, 1.4) * (1.0 - 0.85 * s)
	pos += Vector3(sin(bob_t * 0.5) * 0.009, -absf(sin(bob_t)) * 0.008 + 0.004, 0.0) * bob
	pos.y += sin(time * 1.4) * 0.0016 * (1.0 - s)
	var ld := player.look_delta
	var target := Vector2(clampf(-ld.x * 1.2, -0.03, 0.03), clampf(ld.y * 1.2, -0.03, 0.03))
	sway = sway.lerp(target, minf(1.0, delta * 9.0))
	pos.x += sway.x * (1.0 - 0.7 * s)
	pos.y += sway.y * (1.0 - 0.7 * s)
	rot.y += sway.x * 1.6
	rot.x -= sway.y * 1.6
	kick = lerpf(kick, 0.0, minf(1.0, delta * 13.0))
	pos.z += kick * (1.0 - 0.45 * s)
	rot.x += kick * 1.5
	var sb := smoothstep(0.0, 1.0, sprint_blend)
	pos += Vector3(-0.045, -0.04 + sin(bob_t) * 0.006, 0.03) * sb
	rot += Vector3(-0.2, 0.55, 0.1 + sin(bob_t * 0.5) * 0.03) * sb
	pos.y -= player.land_dip * 0.4
	if reload_t > 0.0:
		var k := 1.0 - reload_t / reload_total
		var dip := sin(clampf(k, 0.0, 1.0) * PI)
		pos += Vector3(0.015, -0.085, 0.02) * dip
		rot += Vector3(-0.3, 0.2, 0.45) * dip
		if m.mag:
			var out := smoothstep(0.1, 0.3, k) * (1.0 - smoothstep(0.45, 0.6, k))
			(m.mag as Node3D).position = Vector3(0, -0.28 * out, 0.02 * out)
	elif m.mag:
		(m.mag as Node3D).position = Vector3.ZERO
	if switch_t > 0.0:
		var sw := sin(clampf(switch_t / 0.45, 0.0, 1.0) * PI)
		pos.y -= 0.26 * sw
		rot.x -= 0.6 * sw
	if heal_t > 0.0:
		var hk := minf(1.0, minf(heal_t, 2.2 - heal_t) * 5.0)
		pos.y -= 0.3 * hk
		rot.x -= 0.5 * hk
	root.position = pos
	root.rotation = rot
	root.visible = not scoped
	# затвор винтовки
	if m.pump:
		var pt := clampf(1.0 - bolt_t / 0.62, 0.0, 1.0) if bolt_t > 0.0 else 1.0
		(m.pump as Node3D).position.z = 0.075 * smoothstep(0.15, 0.45, pt) * (1.0 - smoothstep(0.55, 0.9, pt))
	elif def().get("bolt", false):
		var t := clampf(1.0 - bolt_t / 1.05, 0.0, 1.0) if bolt_t > 0.0 else 1.0
		var lift := smoothstep(0.15, 0.3, t) * (1.0 - smoothstep(0.75, 0.9, t))
		var back := smoothstep(0.3, 0.45, t) * (1.0 - smoothstep(0.55, 0.72, t))
		for part in m.parts:
			var n: Node3D = part[0]
			n.position = (part[1] as Vector3) + Vector3(-0.07 * back, 0, 0)
			n.rotation.x = -0.9 * lift
		root.rotation.z += 0.1 * lift
	# затвор-кожух пистолета
	if def().get("slide", false):
		slide = maxf(0.0, slide - delta * 14.0)
		var locked := 1.0 if (ammo[cur] == 0 and reload_t <= 0.0) else slide
		for part in m.parts:
			(part[0] as Node3D).position = (part[1] as Vector3) + Vector3(-0.03 * locked, 0, 0)
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			flash.visible = false
