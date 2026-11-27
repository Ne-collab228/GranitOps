class_name Enemy
extends CharacterBody3D
## Противник: зрение/слух, патруль, бой с укрытиями, процедурная анимация.

enum St { IDLE, PATROL, INVESTIGATE, COMBAT, DEAD }

const HIPS := 0
const SPINE := 1
const CHEST := 2
const HEAD := 3
const L_ARM := 4
const L_FORE := 5
const R_ARM := 6
const R_FORE := 7
const L_THIGH := 8
const L_SHIN := 9
const R_THIGH := 10
const R_SHIN := 11
const GUN := 12

const SIGMA := [0.021, 0.015, 0.0065]
const DAMAGE := [23.0, 26.0, 52.0]
const HEALTH := [100.0, 140.0, 90.0]
const VIEW := [125.0, 135.0, 270.0]
const DIFF_VIEW := [0.8, 1.0, 1.1]
const DIFF_SIGMA := [1.55, 1.0, 0.72]
const DIFF_DMG := [0.6, 1.0, 1.3]
const DIFF_REACT := [1.5, 1.0, 0.7]

var kind := 0
var hp := 100.0
var state: int = St.IDLE
var route := PackedVector3Array()
var route_i := 0
var hold := false
var home := Vector3.ZERO
var home_yaw := 0.0

var skel: Skeleton3D
var pivot: Node3D
var shape: CollisionShape3D
var glint: MeshInstance3D
var on_screen := true

var awareness := 0.0
var alert := false
var sees := false
var see_time := 0.0
var lost_time := 99.0
var last_known := Vector3.ZERO
var think_t := 0.0
var look_t := 0.0
var wait_t := 0.0
var search_t := 0.0
var advance_count := 0

var path := PackedVector3Array()
var path_i := 0
var speed := 1.5
var yaw := 0.0
var target_yaw := 0.0
var aim_pitch := 0.0
var aim_pitch_s := 0.0
var stuck_t := 0.0
var stuck_pos := Vector3.ZERO
var settle := 30

var crouch := 0.0
var want_crouch := false
var cover_i := -1
var cover_t := 0.0
var cover_try_t := 1.0
var peeking := false

var burst := 0
var shot_t := 0.0
var pause_t := 0.4
var mag := 30
var reload_t := 0.0
var react_t := 0.0
var suppress_t := 0.0

var gait := 0.0
var ready_s := 0.0
var flinch := 0.0
var recoil_s := 0.0
var dead_t := 0.0
var fall_sign := 1.0
var fall_roll := 0.0
## Сколько секунд противник ещё отмечен на экране игрока.
var mark_t := 0.0


func setup(sp: Dictionary) -> void:
	kind = int(sp.kind)
	position = sp.pos
	yaw = float(sp.yaw)
	target_yaw = yaw
	home = sp.pos
	home_yaw = yaw
	route = sp.route
	hold = bool(sp.hold)
	hp = HEALTH[kind]
	if Game.difficulty() == 0:
		hp *= 0.85
	if route.size() > 1:
		state = St.PATROL
	think_t = randf() * 0.2
	look_t = randf_range(1.0, 5.0)


func _ready() -> void:
	collision_layer = Game.L_ENEMY
	collision_mask = Game.L_WORLD | Game.L_FENCE
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	pivot = Node3D.new()
	add_child(pivot)
	pivot.rotation.y = yaw
	skel = SoldierRig.make_skeleton()
	pivot.add_child(skel)
	var mat := Mats.soldier(["soldier_a", "soldier_b", "soldier_c"][kind])
	for lod in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = SoldierRig.mesh(kind, lod)
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-1.3, -0.4, -1.3), Vector3(2.6, 2.8, 2.6))
		if lod == 0:
			mi.visibility_range_end = 34.0
			mi.visibility_range_end_margin = 3.0
		else:
			mi.visibility_range_begin = 34.0
			mi.visibility_range_begin_margin = 3.0
			# на большой карте дальние солдаты (за полкилометра — пара пикселей) не стоят вызова отрисовки
			mi.visibility_range_end = 520.0
			# тени рисуются только вблизи, дальнему упрощённому солдату тень не нужна
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skel.add_child(mi)
		# без пути к скелету меш не деформируется (по умолчанию путь пустой) — солдаты стояли «статуями»
		mi.skeleton = NodePath("..")
		mi.skin = SoldierRig.skin(skel)
	var vis := VisibleOnScreenNotifier3D.new()
	vis.aabb = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0))
	vis.screen_entered.connect(func(): on_screen = true)
	vis.screen_exited.connect(func(): on_screen = false)
	add_child(vis)
	if kind == 2:
		glint = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 0.7)
		glint.mesh = q
		glint.material_override = Mats.sprite("spark", true, true)
		glint.position = Vector3(0, 1.58, 0)
		glint.visible = false
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glint)
	_pose(0.0)


func alive() -> bool:
	return state != St.DEAD


func eye_pos() -> Vector3:
	return global_position + Vector3(0, 1.62 - 0.55 * crouch, 0)


# ------------------------------------------------------------------ восприятие
func _perceive(dt: float) -> void:
	var p: Player = Game.player
	var was := sees
	sees = false
	if p == null or p.dead:
		return
	var eye := eye_pos()
	var tp: Vector3 = p.aim_point()
	var to := tp - eye
	var dist := to.length()
	if dist < VIEW[kind] * DIFF_VIEW[Game.difficulty()]:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var flat := Vector3(to.x, 0, to.z)
		var ang := fwd.angle_to(flat) if flat.length() > 0.01 else 0.0
		var half := deg_to_rad(105.0 if (state == St.COMBAT or alert) else 62.0)
		if ang < half or dist < 3.5:
			var q := PhysicsRayQueryParameters3D.create(eye, tp, Game.L_WORLD)
			if p.vehicle:
				q.exclude = [p.vehicle.get_rid()]
			sees = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if sees:
		last_known = p.global_position
		if state == St.COMBAT:
			if not was and lost_time > 1.0:
				react_t = maxf(react_t, _reaction(dist) * 0.6)
			lost_time = 0.0
			awareness = 1.0
		else:
			var rate := 1.0 / clampf(dist / 32.0, 0.25, 5.0)
			if p.crouching:
				rate *= 0.6
			if p.sprinting:
				rate *= 1.5
			if p.fired_recently():
				rate *= 3.0
			if alert:
				rate *= 1.6
			elif dist > 70.0 and not p.fired_recently():
				rate *= 0.35
			awareness += rate * dt
			if awareness >= 1.0:
				_enter_combat(true, dist)
	else:
		lost_time += dt
		if state != St.COMBAT:
			awareness = maxf(0.0, awareness - dt * 0.2)


func _reaction(dist: float) -> float:
	var base := randf_range(0.45, 0.9) + dist / 220.0
	if kind == 2:
		base += 0.5
	return base * DIFF_REACT[Game.difficulty()]


func _enter_combat(shout: bool, dist := 50.0) -> void:
	if state == St.DEAD:
		return
	var was_combat := state == St.COMBAT
	state = St.COMBAT
	alert = true
	awareness = 1.0
	advance_count = 0
	if not was_combat:
		react_t = _reaction(dist)
		pause_t = 0.0
		path = PackedVector3Array()
	if shout:
		for e in Game.enemies:
			if e != self and is_instance_valid(e) and e.alive() and e.global_position.distance_to(global_position) < 30.0:
				e.alerted(last_known)


func alerted(pos: Vector3) -> void:
	if state == St.DEAD or state == St.COMBAT:
		return
	last_known = pos
	lost_time = 1.5
	_enter_combat(false)


func hear(pos: Vector3, radius: float, investigate := true) -> void:
	if state == St.DEAD or state == St.COMBAT:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	alert = true
	awareness = maxf(awareness, 0.55)
	# чем дальше, тем хуже понимают, откуда стреляли
	var err := d * 0.2
	last_known = pos + Vector3(randf_range(-err, err), 0, randf_range(-err, err))
	state = St.INVESTIGATE
	search_t = 0.0
	target_yaw = atan2(-(pos.x - global_position.x), -(pos.z - global_position.z))
	if investigate and not hold and d < 90.0:
		# осторожно, шагом, а не бегом
		_go(last_known, 2.2)
	else:
		# остальные — оборона на месте: пригнуться и смотреть в сторону звука
		path = PackedVector3Array()
		want_crouch = kind != 2


func suppressed(from: Vector3) -> void:
	if state == St.DEAD:
		return
	suppress_t = 1.6
	if state != St.COMBAT:
		last_known = from
		lost_time = 1.5
		_enter_combat(true)


func _calm() -> void:
	Game.pushers.erase(self)
	_release_cover()
	state = St.PATROL if route.size() > 1 else St.IDLE
	awareness = 0.3
	want_crouch = false
	if state == St.IDLE and not hold:
		_go(home, 1.6)
	target_yaw = home_yaw


func _release_cover() -> void:
	if cover_i >= 0:
		Game.level.cover_claims.erase(cover_i)
		cover_i = -1
	peeking = false


# ------------------------------------------------------------------ решения
func _think(dt: float) -> void:
	match state:
		St.IDLE:
			look_t -= dt
			if look_t <= 0.0:
				look_t = randf_range(3.0, 7.0)
				target_yaw = home_yaw + randf_range(-0.7, 0.7)
		St.PATROL:
			if path.is_empty():
				wait_t -= dt
				if wait_t <= 0.0:
					route_i = (route_i + 1) % route.size()
					_go(route[route_i], 1.5)
					wait_t = randf_range(1.0, 3.5)
		St.INVESTIGATE:
			search_t += dt
			if path.is_empty():
				look_t -= dt
				if look_t <= 0.0:
					look_t = 1.6
					target_yaw += randf_range(-1.5, 1.5)
			if search_t > 16.0:
				_calm()
		St.COMBAT:
			_think_combat(dt)


func _at_cover() -> bool:
	return cover_i >= 0 and path.is_empty()


func _think_combat(dt: float) -> void:
	var p: Player = Game.player
	if p.dead:
		_calm()
		return
	if sees:
		see_time += dt
		if not hold and cover_i < 0:
			cover_try_t -= dt
			if cover_try_t <= 0.0:
				cover_try_t = randf_range(2.0, 4.5)
				if suppress_t > 0.0 or randf() < 0.65:
					_pick_cover()
	else:
		see_time = 0.0
		var hidden := _at_cover() and not peeking
		if not hold and not hidden and lost_time > 2.5 and path.is_empty():
			_release_cover()
			# в атаку идут не больше двух одновременно; остальные ждут в укрытии и прикрывают
			var pushing: bool = Game.pushers.has(self)
			var free_slot: bool = pushing or Game.pushers.size() < 2
			if advance_count < 3 and free_slot and global_position.distance_to(last_known) > 4.0:
				advance_count += 1
				Game.pushers[self] = true
				_go(last_known + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 4.2)
			elif free_slot:
				Game.pushers.erase(self)
				_go(last_known + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)), 2.6)
			elif cover_i < 0:
				_pick_cover()
		if lost_time > 30.0:
			_calm()
			return
	if _at_cover():
		cover_t -= dt
		if cover_t <= 0.0:
			peeking = not peeking
			cover_t = randf_range(1.8, 3.2) if peeking else randf_range(0.9, 2.0)
		want_crouch = not peeking
		if lost_time > 9.0:
			_release_cover()
			want_crouch = false
	else:
		want_crouch = suppress_t > 0.0 and path.is_empty() and kind != 2


func _pick_cover() -> void:
	var pts: PackedVector3Array = Game.level.cover_points
	var p: Player = Game.player
	var eye: Vector3 = p.aim_point()
	var space := get_world_3d().direct_space_state
	var best := -1
	var best_score := -1e9
	var checked := 0
	for i in pts.size():
		var c := pts[i]
		var d := c.distance_to(global_position)
		if d > 16.0 or absf(c.y - global_position.y) > 2.0 or Game.level.cover_claims.has(i):
			continue
		var dp: float = c.distance_to(p.global_position)
		if dp < 8.0:
			continue
		checked += 1
		if checked > 10:
			break
		var low := PhysicsRayQueryParameters3D.create(c + Vector3(0, 0.95, 0), eye, Game.L_WORLD)
		if space.intersect_ray(low).is_empty():
			continue
		var score := -d - absf(dp - 35.0) * 0.1
		var high := PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.62, 0), eye, Game.L_WORLD)
		if space.intersect_ray(high).is_empty():
			score += 8.0
		if score > best_score:
			best = i
			best_score = score
	if best >= 0 and _go(pts[best], 4.4):
		Game.pushers.erase(self)
		cover_i = best
		Game.level.cover_claims[best] = true
		peeking = false
		cover_t = 0.8


func _go(target: Vector3, spd: float) -> bool:
	if hold or not Game.level.nav_ready:
		return false
	var map := get_world_3d().navigation_map
	var pts := NavigationServer3D.map_get_path(map, global_position, target, true)
	if pts.size() < 2:
		path = PackedVector3Array()
		return false
	path = pts
	path_i = 1
	speed = spd
	stuck_t = 0.0
	stuck_pos = global_position
	return true


# ------------------------------------------------------------------ стрельба
func _fire_logic(delta: float) -> void:
	if reload_t > 0.0:
		reload_t -= delta
		return
	if not sees or react_t > 0.0:
		return
	shot_t -= delta
	if burst > 0:
		if shot_t <= 0.0:
			_shoot()
			burst -= 1
			shot_t = 0.105
			if burst == 0:
				pause_t = randf_range(2.2, 3.6) if kind == 2 else randf_range(0.6, 1.5)
	else:
		pause_t -= delta
		if pause_t <= 0.0:
			burst = 1 if kind == 2 else randi_range(2, 4)


func muzzle_pos() -> Vector3:
	return skel.global_transform * (skel.get_bone_global_pose(GUN) * SoldierRig.MUZZLE)


func _shoot() -> void:
	var p: Player = Game.player
	var muzzle := muzzle_pos()
	var bullet_speed := 820.0 if kind == 2 else 715.0
	var target: Vector3 = p.aim_point()
	var dist := muzzle.distance_to(target)
	var t := dist / bullet_speed
	target += p.velocity * t * 0.7
	target.y += 0.5 * 9.81 * t * t
	var d := Game.difficulty()
	var sigma: float = SIGMA[kind] * DIFF_SIGMA[d]
	sigma *= 1.0 + 1.7 * exp(-see_time / 1.3)
	if suppress_t > 0.0:
		sigma *= 1.6
	if not path.is_empty():
		sigma *= 1.5
	sigma *= 1.0 + clampf(p.velocity.length() / 6.0, 0.0, 1.0) * 0.7
	var dir := (target - muzzle).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir)
	dir = (dir + side * randfn(0.0, sigma) + up * randfn(0.0, sigma * 0.8)).normalized()
	Game.ballistics.fire(muzzle, dir, bullet_speed, DAMAGE[kind] * DIFF_DMG[d], self, false, randi() % 3 == 0, muzzle, 0.3)
	Game.fx.flash(muzzle + dir * 0.12)
	Sfx.gunshot("shot_enemy", muzzle, p.global_position, 2.0 if kind == 2 else 0.0)
	recoil_s = 1.0
	mark_t = maxf(mark_t, 5.0)
	mag -= 1
	if mag <= 0:
		mag = 5 if kind == 2 else 30
		reload_t = 2.6


# ------------------------------------------------------------------ движение
func _physics_process(delta: float) -> void:
	if state == St.DEAD:
		return
	var p: Player = Game.player
	if p == null:
		return
	think_t -= delta
	if think_t <= 0.0:
		var far: bool = state != St.COMBAT and global_position.distance_to(p.global_position) > 170.0
		var interval := 0.5 if far else 0.18
		think_t = interval
		_perceive(interval)
		_think(interval)
	suppress_t = maxf(0.0, suppress_t - delta)
	react_t = maxf(0.0, react_t - delta)
	if state == St.COMBAT:
		_fire_logic(delta)
	_move(delta, p)


func _move(delta: float, p: Player) -> void:
	var moving := false
	if not path.is_empty() and not hold:
		var to := path[path_i] - global_position
		to.y = 0.0
		if to.length() < 0.5:
			path_i += 1
			if path_i >= path.size():
				path = PackedVector3Array()
		else:
			var dir := to.normalized()
			velocity.x = move_toward(velocity.x, dir.x * speed, 22.0 * delta)
			velocity.z = move_toward(velocity.z, dir.z * speed, 22.0 * delta)
			moving = true
			if not (state == St.COMBAT and sees):
				target_yaw = atan2(-dir.x, -dir.z)
			stuck_t += delta
			if stuck_t > 1.5:
				if global_position.distance_to(stuck_pos) < 0.4:
					path = PackedVector3Array()
				stuck_t = 0.0
				stuck_pos = global_position
	if not moving:
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 12.0 * delta
	if moving or settle > 0 or not is_on_floor() or absf(velocity.x) + absf(velocity.z) > 0.02:
		move_and_slide()
		settle -= 1
	aim_pitch = 0.0
	if state == St.COMBAT and sees:
		var tp: Vector3 = p.aim_point()
		var d := tp - eye_pos()
		target_yaw = atan2(-d.x, -d.z)
		aim_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	yaw = lerp_angle(yaw, target_yaw, minf(1.0, delta * 7.0))
	pivot.rotation.y = yaw


# ------------------------------------------------------------------ урон
func take_hit(dmg: float, pos: Vector3, dir: Vector3, origin: Vector3) -> Dictionary:
	if state == St.DEAD:
		return {}
	var head: Vector3 = skel.global_transform * (skel.get_bone_global_pose(HEAD) * Vector3(0, 0.15, 0))
	var rel := head - pos
	var along := rel.dot(dir)
	var miss := (rel - dir * along).length()
	var zone := "body"
	var mult := 1.0
	if miss < 0.15 and along > -0.25 and along < 0.7:
		zone = "head"
		mult = 4.0
	else:
		var h := 1.8 - 0.55 * crouch
		var ry := pos.y - global_position.y
		if ry < h * 0.45:
			zone = "legs"
			mult = 0.6
		elif ry < h * 0.62:
			mult = 0.9
	hp -= dmg * mult
	flinch = 1.0
	mark_t = maxf(mark_t, 8.0)
	Game.fx.impact(pos, -dir, "body", dir)
	var killed := hp <= 0.0
	if killed:
		_die(dir)
	else:
		suppress_t = 1.8
		if state != St.COMBAT:
			last_known = origin
			lost_time = 1.5
			_enter_combat(true)
	return {"zone": zone, "killed": killed}


func take_blast(dmg: float, from: Vector3) -> bool:
	if state == St.DEAD:
		return false
	hp -= dmg
	if hp <= 0.0:
		_die((global_position - from).normalized())
		return true
	suppressed(from)
	return false


func _die(dir: Vector3) -> void:
	state = St.DEAD
	Game.pushers.erase(self)
	_release_cover()
	collision_layer = 0
	shape.set_deferred("disabled", true)
	if glint:
		glint.visible = false
	var local := Basis(Vector3.UP, -yaw) * dir
	fall_sign = 1.0 if local.z > 0.0 else -1.0
	fall_roll = randf_range(-0.35, 0.35)
	dead_t = 0.0
	mark_t = 0.0
	if Game.mission:
		Game.mission.drop_ammo(global_position)
	var cold := Mats.soldier_cold(["soldier_a", "soldier_b", "soldier_c"][kind])
	for n in skel.get_children():
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = cold
	Sfx.play_at("hit_body", global_position + Vector3(0, 1, 0), -4.0, randf_range(0.8, 1.0), 6.0, 60.0)


# ------------------------------------------------------------------ анимация
func _process(delta: float) -> void:
	if state == St.DEAD:
		if dead_t < 1.0:
			dead_t += delta
			var k := clampf(dead_t / 0.55, 0.0, 1.0)
			var e := k * k
			pivot.rotation.x = fall_sign * e * 1.5
			pivot.rotation.z = fall_roll * e
			pivot.position.y = e * 0.14
			crouch = move_toward(crouch, 0.0, delta * 3.0)
			_pose(delta, e)
			if dead_t >= 1.0:
				set_process(false)
				set_physics_process(false)
		return
	mark_t = maxf(0.0, mark_t - delta)
	crouch = move_toward(crouch, 1.0 if want_crouch else 0.0, delta * 4.5)
	var cap := shape.shape as CapsuleShape3D
	var hgt := 1.8 - 0.55 * crouch
	if absf(cap.height - hgt) > 0.02:
		cap.height = hgt
		shape.position.y = hgt * 0.5
	if glint:
		glint.visible = state == St.COMBAT and sees and react_t <= 0.4
		if glint.visible:
			var s := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.02)
			glint.scale = Vector3(s, s, s)
	if on_screen and not Game.no_pose:
		# анимация скелета в GDScript дорогая для слабого процессора: дальних солдат обновляем реже
		_pose_acc += delta
		var step := 1
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d2 := global_position.distance_squared_to(cam.global_position)
			step = 1 if d2 < 900.0 else (2 if d2 < 4900.0 else 4)
		if (Engine.get_process_frames() + _pose_phase) % step == 0:
			_pose(_pose_acc)
			_pose_acc = 0.0


var _pose_acc := 0.0
var _pose_phase := randi() % 4


func _pose(delta: float, limp := 0.0) -> void:
	var sp := Vector2(velocity.x, velocity.z).length()
	var mv := clampf(sp / 0.6, 0.0, 1.0) * (1.0 - limp)
	var prev_c := cos(gait)
	var freq := 3.5 + sp * 2.1
	gait += delta * freq * mv
	var s := sin(gait)
	var co := cos(gait)
	# шаг — в момент постановки пятки (нога в крайнем положении)
	if mv > 0.5 and prev_c * co < 0.0 and Game.player and global_position.distance_to(Game.player.global_position) < 28.0:
		Sfx.step(false, global_position, -12.0)
	var run := clampf(sp / 4.4, 0.0, 1.0)
	var c := crouch
	# размах бедра из скорости и частоты: длина шага = скорость / шагов в секунду — ступни не «скользят»
	var step_len := sp / maxf(0.6, freq / TAU * 2.0)
	var amp := clampf(asin(clampf(step_len * 0.5 / 0.88, 0.0, 0.95)), 0.0, 0.8) * mv * (1.0 - 0.3 * c)
	aim_pitch_s = lerpf(aim_pitch_s, aim_pitch, minf(1.0, delta * 8.0))
	var want_ready := 1.0 if state == St.COMBAT else (0.4 if state == St.INVESTIGATE else 0.0)
	ready_s = lerpf(ready_s, want_ready * (1.0 - limp), minf(1.0, delta * 6.0)) if delta > 0.0 else want_ready
	flinch = maxf(0.0, flinch - delta * 5.0)
	recoil_s = maxf(0.0, recoil_s - delta * 12.0)
	var lean := -(0.1 * run + 0.22 * c)
	# таз: подъём в середине опоры, смещение и наклон к опорной ноге, поворот вслед за выносимой ногой
	var bob := (0.016 + 0.026 * run) * absf(co) * mv
	var sway_x := 0.02 * co * (1.0 - 0.6 * run) * mv
	skel.set_bone_pose_position(HIPS, Vector3(sway_x, 0.95 - 0.36 * c + bob - 0.012 * mv, 0))
	skel.set_bone_pose_rotation(HIPS, Quaternion(Vector3.UP, -0.09 * s * mv) * Quaternion(Vector3.BACK, 0.045 * co * mv))
	# корпус компенсирует поворот таза, чтобы оружие не «гуляло»
	skel.set_bone_pose_rotation(SPINE, Quaternion(Vector3.RIGHT, lean + aim_pitch_s * 0.35 - limp * 0.15) * Quaternion(Vector3.UP, 0.07 * s * mv) * Quaternion(Vector3.BACK, -0.04 * co * mv))
	skel.set_bone_pose_rotation(CHEST, Quaternion(Vector3.RIGHT, aim_pitch_s * 0.5 - lean * 0.6) * Quaternion(Vector3.UP, flinch * 0.35 + 0.02 * s * mv))
	skel.set_bone_pose_rotation(HEAD, Quaternion(Vector3.RIGHT, aim_pitch_s * 0.15 - lean * 0.4 + limp * 0.4 - bob * 0.6))
	# бедро: быстрый вынос вперёд, плавный отвод назад
	var asym := 0.12 * sin(2.0 * gait) * amp
	skel.set_bone_pose_rotation(L_THIGH, Quaternion(Vector3.RIGHT, s * amp + asym + 1.15 * c + limp * 0.25))
	skel.set_bone_pose_rotation(R_THIGH, Quaternion(Vector3.RIGHT, -s * amp + asym + 1.15 * c - limp * 0.1))
	# колено: сгибается при переносе ноги вперёд + небольшая амортизация сразу после постановки
	var knee := (0.6 + 0.8 * run) * mv
	var absorb := (0.14 + 0.1 * run) * mv
	var l_knee := knee * pow(maxf(0.0, co), 1.3) + absorb * maxf(0.0, s) * maxf(0.0, -co)
	var r_knee := knee * pow(maxf(0.0, -co), 1.3) + absorb * maxf(0.0, -s) * maxf(0.0, co)
	skel.set_bone_pose_rotation(L_SHIN, Quaternion(Vector3.RIGHT, -l_knee - 1.9 * c - limp * 0.5))
	skel.set_bone_pose_rotation(R_SHIN, Quaternion(Vector3.RIGHT, -r_knee - 1.9 * c - limp * 0.2))
	var gun_pos := Vector3(0.1, -0.02, -0.2).lerp(Vector3(0.13, 0.13, -0.2), ready_s)
	gun_pos.z += recoil_s * 0.03
	gun_pos.y += bob * 0.35
	var gun_rot := Quaternion(Vector3.RIGHT, lerpf(-0.75, 0.0, ready_s) - limp * 0.6) * Quaternion(Vector3.UP, lerpf(0.5, 0.0, ready_s))
	skel.set_bone_pose_position(GUN, gun_pos)
	skel.set_bone_pose_rotation(GUN, gun_rot)
	var rt := gun_pos + gun_rot * Vector3(0.0, -0.06, 0.07)
	var lt := gun_pos + gun_rot * Vector3(0.0, -0.03, -0.24)
	SoldierRig.arm_ik(skel, R_ARM, R_FORE, Vector3(0.21, 0.22, 0), rt, Vector3(0.7, -0.7, 0.3))
	SoldierRig.arm_ik(skel, L_ARM, L_FORE, Vector3(-0.21, 0.22, 0), lt, Vector3(-0.6, -0.8, 0.1))
