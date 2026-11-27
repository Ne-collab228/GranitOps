class_name Player
extends CharacterBody3D
## Игрок: передвижение, камера, здоровье, ввод (сенсор, клавиатура/мышь, геймпад).

const WALK := 4.3
const SPRINT := 6.9
const CROUCH := 2.1
const ADS_SPEED := 2.5
const STAND_H := 1.8
const CROUCH_H := 1.25

var head: Node3D
var cam: Camera3D
var weapons: Weapons
var shape: CollisionShape3D

var yaw := 0.0
var pitch := 0.0
var recoil_off := Vector2.ZERO
var look_delta := Vector2.ZERO
var hp := 100.0
var armor := 60.0
var stamina := 100.0
var stamina_wait := 0.0
var dead := false
var crouching := false
var sprinting := false
var eye_h := 1.62
var lean := 0.0
var suppression := 0.0
var shake_amt := 0.0
var land_dip := 0.0
var step_acc := 0.0
var was_on_floor := true
var fall_v := 0.0
var dead_t := 0.0
var regen_wait := 0.0
var exhausted := false
var sprint_s := 0.0

# состояние ввода на кадр
var in_move := Vector2.ZERO
var in_fire := false
var in_fire_pressed := false
var in_ads := false
var in_interact := false
var _fire_prev := false
var _edges := {}
var _crouch_hold := false

# сенсорное управление
var t_move := Vector2.ZERO
var t_fire := false
var t_ads := false
var _t_key := false
var t_sprint := false
var t_interact := false

var assist := 0.0
var _assist_t := 0.0
var _auto_t := 0.0
var _auto_hold := 0.0
var _auto_fire := false
## Машина, за рулём которой игрок (null — пешком). Камера — от третьего лица, оружие спрятано.
var vehicle: Vehicle
var _veh_interact_prev := true
var _veh_look_t := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	collision_layer = Game.L_PLAYER
	collision_mask = Game.L_WORLD | Game.L_FENCE
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = STAND_H
	shape.shape = cap
	shape.position.y = STAND_H * 0.5
	add_child(shape)
	head = Node3D.new()
	head.position.y = eye_h
	add_child(head)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 2600.0
	cam.fov = float(Settings.data.fov)
	head.add_child(cam)
	cam.make_current()
	var listener := AudioListener3D.new()
	cam.add_child(listener)
	listener.make_current()
	weapons = Weapons.new()
	cam.add_child(weapons)
	weapons.setup(self)
	rotation.y = yaw


func aim_point() -> Vector3:
	if vehicle:
		return vehicle.seat_pos()
	return global_position + Vector3(0, eye_h - 0.28, 0)


# ------------------------------------------------------------------ машина
func enter_vehicle(v: Vehicle) -> void:
	if vehicle or dead or not v.is_free():
		return
	vehicle = v
	v.enter(self)
	_set_crouch(false)
	shape.disabled = true
	collision_layer = 0
	weapons.visible = false
	velocity = Vector3.ZERO
	cam.top_level = true
	_veh_interact_prev = true
	var f := -v.global_transform.basis.z
	yaw = atan2(-f.x, -f.z)
	pitch = -0.15
	Sfx.play("mag_in", -6.0, 0.6)


## Выйти из машины (forced — машина взорвалась/игрок погиб).
func exit_vehicle(_forced := false) -> void:
	if vehicle == null:
		return
	var v := vehicle
	var pos := v.exit_point()
	v.leave()
	vehicle = null
	global_position = pos
	velocity = v.linear_velocity * 0.3
	shape.disabled = false
	collision_layer = Game.L_PLAYER
	weapons.visible = not dead
	cam.top_level = false
	cam.transform = Transform3D()
	pitch = 0.0
	head.rotation.x = 0.0


func _vehicle_frame(delta: float) -> void:
	var v := vehicle
	if not is_instance_valid(v) or v.dead:
		exit_vehicle(true)
		return
	_read_input(delta)
	v.steer_in = -in_move.x
	v.throttle_in = in_move.y
	if in_interact and not _veh_interact_prev:
		_veh_interact_prev = true
		exit_vehicle()
		return
	_veh_interact_prev = in_interact
	# тело игрока едет с машиной (враги целятся в место водителя — aim_point)
	global_position = v.global_position
	# камера: орбита вокруг машины (свайп/мышь — yaw/pitch), на ходу сама уходит за корму
	if look_delta.length() > 0.001:
		_veh_look_t = 1.6
	_veh_look_t = maxf(0.0, _veh_look_t - delta)
	var f := -v.global_transform.basis.z
	if _veh_look_t <= 0.0 and absf(v.speed) > 2.5:
		var hy := atan2(-f.x, -f.z) if v.speed > 0.0 else atan2(f.x, f.z)
		yaw = lerp_angle(yaw, hy, minf(1.0, delta * 1.8))
		pitch = lerpf(pitch, -0.15, minf(1.0, delta * 1.2))
	pitch = clampf(pitch, -0.9, 0.5)
	var bb := v.model.body_aabb
	var target := v.global_position + Vector3(0, bb.end.y + 0.6, 0)
	var dist := bb.size.z * 0.9 + 4.0
	var elev := clampf(0.22 - pitch, -0.2, 1.1)
	var want := target + Basis(Vector3.UP, yaw) * Vector3(0, sin(elev) * dist, cos(elev) * dist)
	var q := PhysicsRayQueryParameters3D.create(target, want, Game.L_WORLD)
	q.exclude = [v.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = (hit.position as Vector3) + ((target - want).normalized() * 0.4)
	var gy := Game.level.ground(want.x, want.z) + 0.5
	want.y = maxf(want.y, gy)
	cam.global_transform = Transform3D(Basis.looking_at(target - want, Vector3.UP), want)
	cam.fov = lerpf(float(Settings.data.fov), float(Settings.data.fov) + 12.0, clampf(absf(v.speed) / 30.0, 0.0, 1.0))
	shake_amt = maxf(0.0, shake_amt - delta * 2.2)
	_vitals(delta)
	look_delta = Vector2.ZERO


func fired_recently() -> bool:
	return weapons.fired_t < 1.0


func act(action: String) -> void:
	_edges[action] = true


func _take(action: String) -> bool:
	if _edges.has(action):
		_edges.erase(action)
		return true
	return false


# ------------------------------------------------------------------ ввод
func _unhandled_input(event: InputEvent) -> void:
	if dead or not Game.playing:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.0022 * float(Settings.data.sens) * zoom_k()
		var inv := -1.0 if Settings.data.invert_y else 1.0
		look_rad(-event.relative.x * k, -event.relative.y * k * inv)
		return
	for a in ["jump", "reload", "grenade", "heal", "firemode", "crouch", "weapon1", "weapon2", "weapon3", "next_weapon", "prev_weapon"]:
		if event.is_action_pressed(a):
			act(a)


func zoom_k() -> float:
	var base := float(Settings.data.fov)
	return lerpf(1.0, float(Settings.data.ads_sens) * cam.fov / base, weapons.ads)


func look_rad(dyaw: float, dpitch: float) -> void:
	yaw += dyaw
	pitch = clampf(pitch + dpitch, -1.45, 1.45)
	look_delta += Vector2(dyaw, dpitch)


## Поворот камеры от сенсорного свайпа (пиксели холста).
func look_touch(rel: Vector2) -> void:
	var m := rel.length()
	var k := 0.0036 * float(Settings.data.sens) * zoom_k() * (0.75 + minf(m / 14.0, 1.0) * 0.6)
	if Settings.data.aim_assist:
		k *= 1.0 - 0.5 * assist
	var inv := -1.0 if Settings.data.invert_y else 1.0
	look_rad(-rel.x * k, -rel.y * k * inv)


func _read_input(delta: float) -> void:
	var mouse_ok := not Settings.touch_ui and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	in_move = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward")) + t_move
	if in_move.length() > 1.0:
		in_move = in_move.normalized()
	var fire_now := t_fire or _auto_fire or (mouse_ok and Input.is_action_pressed("fire"))
	in_fire_pressed = fire_now and not _fire_prev
	in_fire = fire_now
	_fire_prev = fire_now
	in_ads = t_ads or (mouse_ok and Input.is_action_pressed("ads"))
	in_interact = t_interact or Input.is_action_pressed("interact")
	_crouch_hold = Input.is_action_pressed("crouch_hold")
	# геймпад: правый стик
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.15:
		var gk := 2.6 * delta * float(Settings.data.sens) * zoom_k()
		look_rad(-rs.x * gk, -rs.y * gk * 0.75)
	# гироскоп в прицеле
	if Settings.is_mobile and Settings.data.gyro and weapons.ads > 0.4:
		var g := Input.get_gyroscope()
		look_rad(g.y * delta * zoom_k() * 1.4, g.x * delta * zoom_k() * 1.4)


func _update_assist(delta: float) -> void:
	_assist_t -= delta
	if _assist_t > 0.0:
		return
	_assist_t = 0.1
	assist = 0.0
	_auto_fire = false
	var fwd := -cam.global_transform.basis.z
	var origin := cam.global_position
	var best := 0.0
	var zoom := clampf(cam.fov / 75.0, 0.12, 1.0)
	var limit := deg_to_rad(6.0) * maxf(zoom, 0.25)
	var spot_limit := deg_to_rad(4.5) * zoom
	var spot: Enemy = null
	var spot_a := spot_limit
	for e in Game.enemies:
		if not is_instance_valid(e) or not e.alive():
			continue
		var to: Vector3 = e.global_position + Vector3(0, 1.1, 0) - origin
		var d := to.length()
		if d > 320.0:
			continue
		var a2 := fwd.angle_to(to)
		if a2 < limit and d < 180.0:
			best = maxf(best, 1.0 - a2 / limit)
		if a2 < spot_a:
			spot_a = a2
			spot = e
	# обнаружение: навёл прицел на противника в прямой видимости — он отмечается на экране
	if spot:
		var sq := PhysicsRayQueryParameters3D.create(origin, spot.global_position + Vector3(0, 1.2, 0), Game.L_WORLD)
		if get_world_3d().direct_space_state.intersect_ray(sq).is_empty():
			spot.mark_t = maxf(spot.mark_t, 6.0)
	if not Settings.touch_ui:
		return
	if best > 0.0:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 260.0, Game.L_WORLD | Game.L_ENEMY)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var on_target: bool = not hit.is_empty() and hit.collider is Enemy
		assist = best if (on_target or best > 0.5) else best * 0.5
		if Settings.data.auto_fire and on_target:
			_auto_hold += 0.1
			_auto_fire = _auto_hold > 0.15
		else:
			_auto_hold = 0.0
	else:
		_auto_hold = 0.0


# ------------------------------------------------------------------ кадр
func _process(delta: float) -> void:
	if dead:
		dead_t += delta
		head.position.y = lerpf(head.position.y, 0.35, minf(1.0, delta * 3.0))
		cam.rotation.z = lerpf(cam.rotation.z, 0.9, minf(1.0, delta * 2.5))
		return
	if not Game.playing:
		return
	if vehicle:
		_vehicle_frame(delta)
		return
	_read_input(delta)
	_update_assist(delta)
	_actions()
	_move(delta)
	weapons.update(delta)
	_camera(delta)
	_vitals(delta)
	look_delta = Vector2.ZERO


func _actions() -> void:
	if _take("crouch"):
		_set_crouch(not crouching)
	if _take("reload"):
		weapons.start_reload()
	if _take("grenade"):
		weapons.throw_grenade()
	if _take("heal"):
		weapons.use_medkit()
	if _take("firemode"):
		weapons.toggle_mode()
	if Input.is_key_pressed(KEY_T) != _t_key:
		_t_key = not _t_key
		if _t_key and weapons.scoped:
			Settings.data.thermal_bh = not bool(Settings.data.get("thermal_bh", false))
	for i in 3:
		if _take("weapon%d" % (i + 1)):
			weapons.switch_weapon(i)
	if _take("next_weapon"):
		weapons.switch_weapon(weapons.cur + 1)
	if _take("prev_weapon"):
		weapons.switch_weapon(weapons.cur - 1)


func _set_crouch(on: bool) -> void:
	if on == crouching:
		return
	if not on:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, STAND_H + 0.1, 0), Game.L_WORLD)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return
	crouching = on
	var cap := shape.shape as CapsuleShape3D
	cap.height = CROUCH_H if on else STAND_H
	shape.position.y = cap.height * 0.5
	Sfx.play("cloth", -10.0)


func _move(delta: float) -> void:
	if _crouch_hold and not crouching:
		_set_crouch(true)
	var on_floor := is_on_floor()
	var forward := in_move.y > 0.45
	var want_sprint := (Input.is_action_pressed("sprint") or t_sprint) and forward and weapons.heal_t <= 0.0 		and weapons.switch_t <= 0.0 and weapons.ads < 0.2 and not in_ads
	if want_sprint and crouching:
		_set_crouch(false)
	# выдохся — бег вернётся, когда выносливость восстановится на четверть (без дёрганья вкл/выкл)
	if stamina <= 0.5:
		exhausted = true
	elif stamina > 25.0:
		exhausted = false
	sprinting = want_sprint and not crouching and not exhausted and (on_floor or sprinting)
	sprint_s = move_toward(sprint_s, 1.0 if sprinting else 0.0, delta * 4.0)
	var spd := WALK
	if crouching:
		spd = CROUCH
	elif sprinting:
		spd = SPRINT
	if weapons.ads > 0.5:
		spd = minf(spd, ADS_SPEED)
	if in_move.y < -0.1:
		spd *= 0.8
	spd *= float(weapons.def().get("move", 1.0))
	var b := Basis(Vector3.UP, yaw)
	var wish := b * Vector3(in_move.x, 0, -in_move.y) * spd
	var accel := (16.0 if sprinting else 30.0) if on_floor else 5.0
	velocity.x = move_toward(velocity.x, wish.x, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * delta)
	if on_floor:
		if _take("jump") and stamina > 8.0:
			if crouching:
				_set_crouch(false)
			else:
				velocity.y = 4.7
				stamina -= 10.0
				stamina_wait = 0.8
		elif velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= 13.0 * delta
		_edges.erase("jump")
	if not on_floor:
		fall_v = minf(fall_v, velocity.y)
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not was_on_floor:
		var v := -fall_v
		land_dip = clampf(v * 0.02, 0.0, 0.25)
		if v > 4.0:
			Sfx.step(false, global_position, -5.0, true)
		if v > 11.5:
			take_damage((v - 11.5) * 9.0, global_position)
		fall_v = 0.0
	was_on_floor = now_floor
	# выносливость
	if sprinting:
		stamina = maxf(0.0, stamina - 8.5 * delta)
		stamina_wait = 1.0
	else:
		stamina_wait -= delta
		if stamina_wait <= 0.0:
			stamina = minf(100.0, stamina + 15.0 * delta)
	# шаги
	var sp := Vector2(velocity.x, velocity.z).length()
	if now_floor and sp > 0.8:
		step_acc += sp * delta
		var stride := 2.5 if sprinting else (1.7 if crouching else 2.1)
		if step_acc > stride:
			step_acc = 0.0
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position - Vector3(0, 0.5, 0), Game.L_WORLD)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			var hard: bool = not hit.is_empty() and hit.collider.get_meta("surf", "dirt") != "dirt"
			Sfx.step(hard, global_position, -14.0 if crouching else (-6.0 if sprinting else -10.0), true)
			if not crouching:
				Game.noise(global_position, 17.0 if sprinting else 8.0)


func _camera(delta: float) -> void:
	rotation.y = yaw
	var target_h := 1.07 if crouching else 1.62
	eye_h = lerpf(eye_h, target_h, minf(1.0, delta * 9.0))
	land_dip = lerpf(land_dip, 0.0, minf(1.0, delta * 7.0))
	head.position.y = eye_h - land_dip
	head.rotation.x = pitch
	# наклон из-за угла
	var want_lean := 0.0
	if not sprinting:
		want_lean = Input.get_axis("lean_left", "lean_right")
	if want_lean != 0.0:
		var side := global_transform.basis.x * want_lean
		var q := PhysicsRayQueryParameters3D.create(head.global_position, head.global_position + side * 0.6, Game.L_WORLD)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			want_lean = 0.0
	lean = lerpf(lean, want_lean, minf(1.0, delta * 8.0))
	recoil_off = recoil_off.lerp(Vector2.ZERO, 1.0 - exp(-delta * 9.0))
	shake_amt = maxf(0.0, shake_amt - delta * 2.2)
	suppression = maxf(0.0, suppression - delta * 0.6)
	var sh := shake_amt * shake_amt
	var t := Time.get_ticks_msec() * 0.001
	var sway_a := 0.0
	if weapons.scoped:
		sway_a = 0.0028 * (0.55 if crouching else 1.0) * (1.0 + suppression * 2.0) * (1.0 + (1.0 - stamina / 100.0))
	# покачивание камеры на бегу
	var run_k := sprint_s * clampf(Vector2(velocity.x, velocity.z).length() / SPRINT, 0.0, 1.0)
	var bt := weapons.bob_t
	cam.position = Vector3(lean * 0.36 + sin(t * 47.0) * sh * 0.03 + sin(bt * 0.5) * 0.012 * run_k,
		cos(t * 53.0) * sh * 0.03 - absf(sin(bt * 0.5)) * 0.022 * run_k, 0)
	cam.rotation = Vector3(
		recoil_off.x + sin(t * 0.9) * sway_a + sin(t * 61.0) * sh * 0.02,
		recoil_off.y + sin(t * 1.37 + 1.0) * sway_a,
		-lean * 0.13 + sin(t * 39.0) * sh * 0.03 + sin(bt * 0.5) * 0.006 * run_k)
	var base := float(Settings.data.fov)
	var d := weapons.def()
	var a := smoothstep(0.0, 1.0, weapons.ads)
	cam.fov = lerpf(base + 5.0 * smoothstep(0.0, 1.0, sprint_s), float(d.ads_fov), a)


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	pitch = clampf(pitch + p * 0.45, -1.45, 1.45)
	yaw += y * 0.6
	recoil_off += Vector2(p * 0.55, y * 0.4)


func shake(amount: float) -> void:
	shake_amt = clampf(maxf(shake_amt, amount), 0.0, 1.5)


func suppress(amount: float) -> void:
	suppression = clampf(suppression + amount, 0.0, 1.0)


# ------------------------------------------------------------------ здоровье
func _vitals(delta: float) -> void:
	Sfx.loop("heartbeat", hp < 35.0, -4.0)
	regen_wait -= delta
	if Game.difficulty() == 0 and regen_wait <= 0.0 and hp < 45.0:
		hp = minf(45.0, hp + 4.0 * delta)


func heal(amount: float) -> void:
	hp = minf(100.0, hp + amount)


func take_damage(dmg: float, from: Vector3) -> void:
	if dead or not Game.playing:
		return
	var d := dmg
	if armor > 0.0:
		var absorbed := d * 0.4
		armor = maxf(0.0, armor - absorbed * 1.4)
		d -= absorbed
	hp -= d
	Game.stats.damage += d
	regen_wait = 6.0
	suppress(0.5)
	shake(0.4)
	Sfx.play("hit_body", -2.0, randf_range(0.9, 1.1))
	if Settings.is_mobile and Settings.data.vibration:
		Input.vibrate_handheld(60)
	if Game.hud:
		var to := from - global_position
		Game.hud.damage_from(atan2(-to.x, -to.z) - yaw)
	if hp <= 0.0:
		hp = 0.0
		if vehicle:
			exit_vehicle(true)
		dead = true
		Sfx.loop("heartbeat", false)
		weapons.visible = false
		Game.main.on_player_dead()


func on_hit_enemy(res: Dictionary, dist: float) -> void:
	Game.stats.hits += 1
	var killed: bool = res.get("killed", false)
	var headshot: bool = res.get("zone", "") == "head"
	if killed:
		Game.stats.kills += 1
		if headshot:
			Game.stats.headshots += 1
		Game.stats.longest = maxf(float(Game.stats.longest), dist)
		Sfx.play("killmark", -4.0)
	else:
		Sfx.play("hitmark", -6.0, 1.2 if headshot else 1.0)
	if Game.hud:
		Game.hud.hit_marker(killed, headshot)
