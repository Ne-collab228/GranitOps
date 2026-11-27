class_name Vehicle
extends VehicleBody3D
## Машина: физика VehicleBody3D (лучевые колёса), водитель — игрок или ИИ (езда по дорогам карты),
## повреждения от пуль/взрывов, взрыв и остов. Модель — VehicleModel (tools/flatten_vehicles.gd).
## Пустая машина «спит» (freeze), дальняя ИИ-машина едет по маршруту без физики (кинематически).

const SUSP := 0.22
const LOD_DIST := 40.0  # ближе — кузов + отдельные колёса (по 1 вызову), дальше — один меш с впаянными колёсами
## Дальше этого от игрока ИИ-машина едет без физики.
const FAR_SIM := 230.0

var vid := ""
var def: Dictionary
var model: VehicleModel
var hp := 800.0
var hp_max := 800.0
var dead := false
## Игрок за рулём (null — нет).
var player: Player
## ИИ: маршрут (точки по дороге), команда для высадки (словари как у Level.enemy_spawns).
var ai := false
var route := PackedVector3Array()
var route_i := 0
var route_dir := 1
var crew: Array = []
var ai_state := 0  # 0 — едет, 1 — высадка/стоит
var cruise := 12.0
## Ввод: руль −1..1, газ −1..1 (минус — тормоз/задний ход).
var steer_in := 0.0
var throttle_in := 0.0
var speed := 0.0

var wheels: Array[VehicleWheel3D] = []
var _near: Array[GeometryInstance3D] = []
var _far_mi: MeshInstance3D
var _burn_t := 0.0
var _stuck_t := 0.0
## ИИ: сколько секунд упирается в препятствие на газу и сколько раз подряд пришлось сдавать назад.
var _ai_stuck_t := 0.0
var _ai_stuck_n := 0
var _ai_stuck_win := 0.0
var _prog_t := 0.0
var _prog_pos := Vector3.ZERO
var _rev_stuck_t := 0.0
var _fwd_force_t := 0.0
var _reverse_t := 0.0
var _kin := false
var _see_t := 0.0
var _hit_cool := {}
var _avoid_side := 0.0
var _avoid_t := 0.0
var _route_ang := 0.0


func setup(id: String, color_i: int, xf: Transform3D) -> void:
	vid = id
	def = VehDefs.DEFS[id]
	model = load("res://assets/vehicles/%s.res" % id)
	hp_max = float(def.hp)
	hp = hp_max
	global_transform = xf
	color_i = color_i % model.bodies.size()
	var body := MeshInstance3D.new()
	body.mesh = model.bodies[color_i]
	body.visibility_range_end = LOD_DIST
	body.visibility_range_end_margin = 4.0
	add_child(body)
	_near.append(body)
	_far_mi = MeshInstance3D.new()
	_far_mi.mesh = model.bodies_far[color_i]
	_far_mi.visibility_range_begin = LOD_DIST
	_far_mi.visibility_range_begin_margin = 4.0
	_far_mi.visibility_range_end = 450.0
	_far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_far_mi)


func _ready() -> void:
	collision_layer = Game.L_WORLD
	collision_mask = Game.L_WORLD | Game.L_FENCE
	set_meta("surf", "metal")
	mass = float(def.mass)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, model.wheel_r * 0.7, 0)  # низкий центр масс — иначе машина кувыркается на поворотах
	angular_damp = 0.9
	linear_damp = 0.05
	can_sleep = true
	var bb := model.body_aabb
	var clear := model.wheel_r * 1.1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bb.size.x * 0.96, maxf(0.5, bb.end.y - clear), bb.size.z * 0.98)
	cs.shape = box
	cs.position = Vector3(bb.get_center().x, (clear + bb.end.y) * 0.5, bb.get_center().z)
	add_child(cs)
	var n := model.hubs.size()
	for i in n:
		var hp_pos: Vector3 = model.hubs[i]
		var w := VehicleWheel3D.new()
		w.position = hp_pos + Vector3(0, SUSP, 0)
		w.wheel_radius = model.wheel_r
		w.wheel_rest_length = SUSP
		w.suspension_travel = 0.26
		w.suspension_stiffness = 38.0
		w.damping_compression = 1.9
		w.damping_relaxation = 2.4
		w.suspension_max_force = mass * 14.0
		w.wheel_friction_slip = 2.6 * float(def.offroad) + 0.6
		w.wheel_roll_influence = 0.03
		var front := i < 2
		w.use_as_steering = front
		w.use_as_traction = not front or bool(def.mil)
		var mi := MeshInstance3D.new()
		mi.mesh = model.wheel
		if hp_pos.x < 0.0:
			mi.rotation.y = PI
		mi.visibility_range_end = LOD_DIST
		mi.visibility_range_end_margin = 4.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(mi)
		_near.append(mi)
		add_child(w)
		wheels.append(w)
	_park(true)


## Отладка ИИ: одна строка состояния (для --vehtest).
func ai_debug() -> String:
	var tgt := route[route_i] if route.size() > 0 else Vector3.ZERO
	return "%s (%.0f,%.0f) v=%.0f км/ч ai=%s st=%d kin=%s точка %d/%d до неё %.0f м газ=%.2f руль=%.2f торм=%.0f застр=%.1f зад=%.1f сила=%.0f к=%d |v|=%.1f" % [vid, global_position.x, global_position.z, speed * 3.6, ai, ai_state, _kin, route_i, route.size(), Vector2(tgt.x - global_position.x, tgt.z - global_position.z).length(), throttle_in, steer_in, brake, _stuck_t, _reverse_t, engine_force, wheels.filter(func(w): return w.is_in_contact()).size(), linear_velocity.length()]


func is_free() -> bool:
	return not dead and player == null and not ai


func display_name() -> String:
	return String(def.name)


## Стоянка: физика выключена (бесплатно), пока никто не сел и ничто не толкнуло.
func _park(on: bool) -> void:
	if on:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
		engine_force = 0.0
		brake = 40.0
	else:
		freeze = false
		_kin = false
		sleeping = false


func enter(p: Player) -> void:
	player = p
	_park(false)
	brake = 0.0


func leave() -> void:
	player = null
	steer_in = 0.0
	throttle_in = 0.0
	engine_force = 0.0
	brake = 30.0


## Точка выхода: слева от водителя, иначе справа/сзади — где свободно.
func exit_point() -> Vector3:
	var bb := model.body_aabb
	var space := get_world_3d().direct_space_state
	for off in [Vector3(-bb.size.x * 0.5 - 0.9, 0, bb.position.z * 0.3), Vector3(bb.size.x * 0.5 + 0.9, 0, bb.position.z * 0.3), Vector3(0, 0, bb.end.z + 1.2)]:
		var p: Vector3 = global_transform * (off as Vector3)
		var q := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.4
		q.shape = sph
		q.transform = Transform3D(Basis(), p + Vector3(0, 1.0, 0))
		q.collision_mask = Game.L_WORLD | Game.L_FENCE
		q.exclude = [get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return p + Vector3(0, 0.3, 0)
	return global_position + Vector3(0, bb.end.y + 0.5, 0)


## Место водителя (для камеры/прицеливания врагов).
func seat_pos() -> Vector3:
	var bb := model.body_aabb
	return global_transform * Vector3(-bb.size.x * 0.2, bb.end.y * 0.72, bb.position.z * 0.25)


func _physics_process(delta: float) -> void:
	if dead:
		_burn_t -= delta
		return
	speed = linear_velocity.dot(-global_transform.basis.z)
	# страховка от физических «выстрелов» (глубокое проникновение при пробуждении/телепорте): скорость не больше 1.6 vmax
	if not freeze and linear_velocity.length() > float(def.vmax) * 1.6:
		if Game.test_mode():
			print("VEH ВЫСТРЕЛ ", ai_debug())
		linear_velocity = linear_velocity.limit_length(float(def.vmax))
		angular_velocity = Vector3.ZERO
	if ai:
		_ai(delta)
	if freeze and not _kin:
		return
	if player != null or ai:
		_drive(delta)
	_ram(delta)


func _drive(delta: float) -> void:
	var vmax: float = def.vmax
	if ai and ai_state == 1:
		# тревога: плавно встать (тормозом, без тяги — иначе у самой остановки включался задний ход)
		engine_force = 0.0
		brake = float(def.brake)
		steering = move_toward(steering, 0.0, delta * 2.2)
		return
	var k := clampf(absf(speed) / vmax, 0.0, 1.0)
	var max_steer := lerpf(0.55, 0.07, sqrt(k))
	steering = move_toward(steering, steer_in * max_steer, delta * 2.2)
	var power: float = float(def.power) * 1.6
	brake = 0.0
	engine_force = 0.0
	if throttle_in > 0.05:
		if speed < -1.0:
			brake = float(def.brake) * throttle_in
		elif speed < vmax:
			engine_force = -power * throttle_in * (1.0 - k * k * 0.7)  # в VehicleBody3D положительная сила тянет к +Z, а перёд модели — −Z
	elif throttle_in < -0.05:
		if speed > 1.0:
			brake = float(def.brake) * -throttle_in
		elif speed > -vmax * 0.3:
			engine_force = -power * 0.6 * throttle_in
	else:
		brake = 1.5
	# в воздухе гасим крен/тангаж, чтобы не приземляться на бок; на земле — прижимная сила от скорости
	var grounded := false
	for w in wheels:
		if w.is_in_contact():
			grounded = true
			break
	if not grounded:
		angular_velocity.x *= 1.0 - minf(1.0, delta * 3.0)
		angular_velocity.z *= 1.0 - minf(1.0, delta * 3.0)
	else:
		apply_central_force(Vector3(0, -absf(speed) * mass * 0.35, 0))
	# переворот: если машина легла на бок и стоит — аккуратно поставить на колёса
	if global_transform.basis.y.y < 0.3 and linear_velocity.length() < 1.0:
		_stuck_t += delta
		if _stuck_t > 2.5:
			_stuck_t = 0.0
			var f := -global_transform.basis.z
			f.y = 0.0
			global_transform = Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3(0, 1.2, 0))
			angular_velocity = Vector3.ZERO
	else:
		_stuck_t = 0.0


## Наезд: враги/игрок перед машиной на скорости получают урон.
func _ram(_delta: float) -> void:
	var v := linear_velocity.length()
	if v < 4.0:
		return
	var bb := model.body_aabb
	var reach := bb.size.z * 0.5 + 0.6
	var now := Time.get_ticks_msec()
	for e in Game.enemies:
		if not is_instance_valid(e) or not e.alive():
			continue
		var rel: Vector3 = global_transform.affine_inverse() * (e as Enemy).global_position
		if absf(rel.x) < bb.size.x * 0.5 + 0.4 and absf(rel.z) < reach and rel.y > -1.0 and rel.y < 2.0:
			if int(_hit_cool.get(e, 0)) > now:
				continue
			_hit_cool[e] = now + 600
			var killed: bool = (e as Enemy).take_blast(v * v * 2.2, global_position)
			if killed and player != null:
				player.on_hit_enemy({"zone": "body", "killed": true}, 0.0)
			Sfx.play_at("hit_body", (e as Enemy).global_position + Vector3(0, 1, 0), 0.0, 0.8, 8.0, 80.0)
	var p: Player = Game.player
	if p and not p.dead and p.vehicle == null and ai:
		var rp: Vector3 = global_transform.affine_inverse() * p.global_position
		if absf(rp.x) < bb.size.x * 0.5 + 0.4 and absf(rp.z) < reach and rp.y > -1.0 and rp.y < 2.0:
			if int(_hit_cool.get(p, 0)) <= now:
				_hit_cool[p] = now + 800
				p.take_damage(v * v * 1.2, global_position)


# ------------------------------------------------------------------ повреждения
func take_hit(dmg: float, pos: Vector3, from_player: bool) -> void:
	if dead:
		return
	hp -= dmg * 0.8
	if from_player and ai:
		_alarm()
	if hp <= 0.0:
		explode(from_player)
	elif hp < hp_max * 0.3 and _burn_t <= 0.0:
		_burn_t = 999.0
		Game.fx.fire(global_transform * Vector3(0, model.body_aabb.end.y * 0.6, model.body_aabb.position.z * 0.6), 0.6)


func take_blast(dmg: float, from: Vector3) -> void:
	if dead:
		return
	if freeze and not ai and player == null:
		_park(false)
	apply_central_impulse((global_position - from).normalized() * dmg * 6.0 + Vector3(0, dmg * 4.0, 0))
	take_hit(dmg * 2.5, global_position, true)


func explode(by_player := true) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	var c := global_transform * Vector3(0, model.body_aabb.end.y * 0.5, 0)
	var p := player
	if p != null:
		p.exit_vehicle(true)
	Game.fx.explosion(c, 9.0, 260.0)
	Game.fx.fire(c, 1.3)
	var burnt := Mats.flat(Color(0.06, 0.055, 0.05), 0.95)
	for g in _near:
		g.material_override = burnt
	_far_mi.material_override = burnt
	engine_force = 0.0
	brake = 60.0
	ai = false
	# часть экипажа успевает выброситься: раненые, настороже; остальные гибнут вместе с машиной
	if not crew.is_empty():
		call_deferred("_dismount", true)  # взрыв может прийти из физического колбэка — спавн экипажа вне его


# ------------------------------------------------------------------ ИИ-водитель
func start_ai(path: PackedVector3Array, crew_spawns: Array, start_i := 0) -> void:
	ai = true
	route = path
	route_i = clampi(start_i, 0, path.size() - 1)
	crew = crew_spawns
	ai_state = 0
	_prog_pos = global_position
	cruise = randf_range(10.0, 14.0)


var odo := 0.0  # пройденный путь ИИ-машины (для --vehtest)
var _odo_prev := Vector3.INF


func _ai(delta: float) -> void:
	if _odo_prev != Vector3.INF:
		odo += global_position.distance_to(_odo_prev)
	_odo_prev = global_position
	if ai_state == 1 or route.size() < 2:
		steer_in = 0.0
		throttle_in = -signf(speed) if absf(speed) > 0.5 else 0.0  # тормозить в любую сторону (в _drive минус при движении вперёд — тормоз, плюс при заднем ходе — тоже)
		if absf(speed) < 0.6 and not crew.is_empty():
			_dismount()
		return
	var p: Player = Game.player
	var pd := global_position.distance_to(p.global_position) if p else 9999.0
	# заметить игрока: близко и в прямой видимости (раз в 0.4 с)
	_see_t -= delta
	if p and not p.dead and pd < 85.0 and _see_t <= 0.0:
		_see_t = 0.4
		var q := PhysicsRayQueryParameters3D.create(seat_pos() + Vector3(0, 0.3, 0), p.aim_point(), Game.L_WORLD)
		q.exclude = [get_rid()]
		if p.vehicle:
			q.exclude.append(p.vehicle.get_rid())
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_alarm()
			return
	# дальняя машина — без физики: едет по точкам маршрута с крейсерской скоростью
	var want_kin := pd > FAR_SIM
	# (ИИ-машина стартует «запаркованной» — статичной: при первом же кадре в физической зоне будим её)
	if want_kin != _kin or (not _kin and freeze):
		var was_kin := _kin
		_kin = want_kin
		if _kin:
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
		else:
			freeze = false
			sleeping = false
			brake = 0.0
			if was_kin:
				linear_velocity = -global_transform.basis.z * cruise * 0.8
	var target := route[route_i]
	var to := target - global_position
	to.y = 0.0
	if to.length() < (6.0 if not _kin else 2.0):
		route_i += route_dir
		if route_i >= route.size() or route_i < 0:
			route_dir = -route_dir
			route_i = clampi(route_i + route_dir * 2, 0, route.size() - 1)
		return
	if _kin:
		var step := minf(cruise * delta, to.length())
		var np := global_position + to.normalized() * step
		np.y = Game.level.ground(np.x, np.z)
		var fwd := to.normalized()
		global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), np)
		return
	# точка впереди по маршруту (сглаживает повороты)
	var ahead := target
	var j := route_i + route_dir
	if j >= 0 and j < route.size() and to.length() < 14.0:
		ahead = target.lerp(route[j], 0.5)
	var local := global_transform.affine_inverse() * ahead
	var ang := atan2(-local.x, -local.z)
	if _fwd_force_t > 0.0:
		# задний ход упёрся — выбираемся вперёд, руль в сторону цели
		_fwd_force_t -= delta
		steer_in = signf(ang)
		throttle_in = 0.6
		return
	if (absf(ang) > deg_to_rad(110.0) or _reverse_t > 0.0) and absf(speed) < 0.5 and _reverse_t > 0.0:
		_rev_stuck_t += delta
		if _rev_stuck_t > 2.0:
			_rev_stuck_t = 0.0
			_reverse_t = 0.0
			_fwd_force_t = 2.5
			return
	elif absf(speed) > 1.0:
		_rev_stuck_t = 0.0
	if absf(ang) > deg_to_rad(110.0) or _reverse_t > 0.0:
		# цель сзади: задний ход с обратным рулём (разворот в несколько приёмов)
		_reverse_t = maxf(_reverse_t - delta, 0.0) if absf(ang) < deg_to_rad(60.0) else 1.2
		steer_in = -signf(ang)
		throttle_in = -0.7
		return
	steer_in = clampf(ang * 1.8, -1.0, 1.0)
	var want := cruise * lerpf(1.0, 0.45, clampf(absf(ang) / 0.8, 0.0, 1.0))
	# объезд препятствий: лучи вперёд, руль в свободную сторону, торможение заранее
	_route_ang = ang
	var av := _ai_avoid(delta)
	var urg: float = av.y
	if urg > 0.0:
		steer_in = clampf(lerpf(steer_in, av.x * 0.9, clampf(urg * 1.6, 0.0, 1.0)), -1.0, 1.0)
		want *= lerpf(1.0, 0.45, urg)
	throttle_in = clampf((want - speed) * 0.4, -1.0, 1.0)
	# нет продвижения: за 10 с сдвинулись меньше чем на 9 м (толчёмся перед непроходимым местом) — ехать обратно по маршруту
	_prog_t += delta
	if _prog_t > 10.0:
		if global_position.distance_to(_prog_pos) < 9.0:
			route_dir = -route_dir
			route_i = clampi(route_i + route_dir * 2, 0, route.size() - 1)
			_ai_stuck_n = 0
		_prog_t = 0.0
		_prog_pos = global_position
	# застрял — сдать назад; два раза за 40 с в одном месте — дорога непроходима, развернуться и ехать обратно по маршруту
	_ai_stuck_win = maxf(_ai_stuck_win - delta, 0.0)
	if _ai_stuck_win <= 0.0:
		_ai_stuck_n = 0
	if absf(speed) < 0.7 and throttle_in > 0.3:
		_ai_stuck_t += delta
		if _ai_stuck_t > 1.6:
			_ai_stuck_t = 0.0
			_ai_stuck_n += 1
			_ai_stuck_win = 40.0
			_reverse_t = 1.8
			if _ai_stuck_n >= 2:
				_ai_stuck_n = 0
				route_dir = -route_dir
				route_i = clampi(route_i + route_dir * 2, 0, route.size() - 1)
	elif absf(speed) > 3.0:
		_ai_stuck_t = 0.0


## Лучи вперёд на уровне капота: три параллельных (ширина машины) и веер ±25°/±50°.
## Возвращает Vector2(сторона объезда: + влево, срочность 0..1). Сторона запоминается на 1.5 с (без «виляния»).
func _ai_avoid(delta: float) -> Vector2:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		return Vector2.ZERO
	fwd = fwd.normalized()
	var side_v := fwd.cross(Vector3.UP)  # вправо
	var half_w := model.body_aabb.size.x * 0.5 + 0.2
	var reach := 8.0 + maxf(speed, 0.0) * 1.5
	var o := global_position + Vector3(0, 0.9, 0) + fwd * (model.body_aabb.size.z * 0.5 - 0.3)
	var space := get_world_3d().direct_space_state
	var mask := Game.L_WORLD | Game.L_FENCE
	var ray := func(from: Vector3, dir: Vector3, l: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * l, mask)
		q.exclude = [get_rid()]
		var h := space.intersect_ray(q)
		return l if h.is_empty() else from.distance_to(h.position)
	var dc: float = ray.call(o, fwd, reach)
	var dl: float = ray.call(o - side_v * half_w, fwd, reach)
	var dr: float = ray.call(o + side_v * half_w, fwd, reach)
	var front := minf(dc, minf(dl, dr))
	_avoid_t -= delta
	if front >= reach:
		if _avoid_t < 0.0:
			_avoid_side = 0.0
		return Vector2.ZERO
	# куда свободнее: веер
	var fl := 0.0
	var fr := 0.0
	for a in [25.0, 50.0]:
		fl += ray.call(o, fwd.rotated(Vector3.UP, deg_to_rad(a)), reach)
		fr += ray.call(o, fwd.rotated(Vector3.UP, deg_to_rad(-a)), reach)
	if _avoid_t <= 0.0 or _avoid_side == 0.0:
		# при равных шансах — в сторону цели (знак руля к маршруту)
		var side := 1.0 if fl > fr else -1.0
		if absf(fl - fr) < 2.0:
			side = signf(_route_ang) if absf(_route_ang) > 0.05 else 1.0
		_avoid_side = side
		_avoid_t = 1.5
	var urg := clampf(1.0 - (front - 2.5) / maxf(reach - 2.5, 1.0), 0.0, 1.0)
	return Vector2(_avoid_side, urg)


## Тревога: остановиться и высадить экипаж.
func _alarm() -> void:
	if not ai or ai_state == 1:
		return
	ai_state = 1
	if _kin:
		_kin = false
		freeze = false


func _dismount(blast := false) -> void:
	var p: Player = Game.player
	var sides := [Vector3(-1.4, 0, -0.6), Vector3(1.4, 0, -0.6), Vector3(-1.4, 0, 0.8), Vector3(1.4, 0, 0.8)]
	var bb := model.body_aabb
	for i in crew.size():
		if blast and i % 2 == 1:
			continue  # при взрыве выживает каждый второй
		var sp: Dictionary = (crew[i] as Dictionary).duplicate()
		var off: Vector3 = sides[i % sides.size()]
		off.x *= bb.size.x * 0.5 + 0.5
		var pos: Vector3 = global_transform * off
		pos.y = Game.level.ground(pos.x, pos.z) + 0.1
		sp.pos = pos
		sp.yaw = global_rotation.y
		sp.route = PackedVector3Array()
		sp.hold = false
		var e: Enemy = Game.main.spawn_enemy(sp)
		if blast:
			e.hp = 40.0
		if p:
			e.alerted(p.global_position)
	crew.clear()
	if blast:
		return
	ai = false
	throttle_in = 0.0
	steer_in = 0.0
	engine_force = 0.0
	_park(false)
	brake = 40.0
