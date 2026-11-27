class_name Mission
extends Node
## Задачи операции: подрыв РЛС и топливного склада, разведданные, эвакуация.

var objectives: Array = []
var charges: Array = []
var hold_t := 0.0
var hold_id := ""
var _veh_target: Vehicle
var finished := false


func setup(level: Level) -> void:
	objectives = level.mission_objectives()
	_pick_mesh = BoxMesh.new()
	_pick_mesh.size = Vector3(0.3, 0.17, 0.2)


var _pick_mesh: BoxMesh
var _hint_t := 0.0


## С убитого противника выпадает подсумок с патронами (подбирается автоматически).
func drop_ammo(pos: Vector3) -> void:
	if randf() > (0.9 if Game.difficulty() == 0 else 0.7):
		return
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _pick_mesh
	mi.material_override = Mats.flat(Color(0.2, 0.26, 0.14), 0.8)
	n.add_child(mi)
	var strip := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.31, 0.04, 0.21)
	strip.mesh = sb
	strip.material_override = Mats.emissive(Color(1.0, 0.8, 0.2), 1.5)
	n.add_child(strip)
	n.position = pos + Vector3(randf_range(-0.5, 0.5), 0.12, randf_range(-0.5, 0.5))
	n.rotation.y = randf() * TAU
	add_child(n)
	Game.pickups.append(n)


func _pickups(p: Player) -> void:
	for n in Game.pickups:
		if is_instance_valid(n) and (n as Node3D).global_position.distance_to(p.global_position) < 1.8:
			p.weapons.add_ammo(1.0)
			var extra := ""
			if randf() < 0.2 and p.weapons.grenades < 4:
				p.weapons.grenades += 1
				extra = " и граната"
			Sfx.play("mag_in", -5.0)
			Game.hud.show_message("Подобраны патроны" + extra, 2.0)
			n.queue_free()
	Game.pickups = Game.pickups.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())


## Общий список целей для интерфейса (метки над объектами, список задач, карты). Любая карта задаёт цели
## через Level.mission_objectives(): id, title, pos, done, locked. Номер — порядок в списке (последняя обычно эвакуация).
## Возвращает [{num, id, title, pos, done, locked, lz}]; lz — цель выхода к точке эвакуации (id "lz").
func goals() -> Array:
	var out: Array = []
	var i := 0
	for o in objectives:
		i += 1
		out.append({"num": i, "id": String(o.id), "title": String(o.title), "pos": o.pos as Vector3,
			"done": bool(o.done), "locked": bool(o.get("locked", false)), "lz": String(o.id) == "lz"})
	return out


func _obj(id: String) -> Dictionary:
	for o in objectives:
		if o.id == id:
			return o
	return {}


func _process(delta: float) -> void:
	if not Game.playing or finished:
		return
	var p: Player = Game.player
	if p == null or p.dead:
		return
	Game.stats.time += delta
	_interact(delta, p)
	_charges(delta)
	_pickups(p)
	_hint_t -= delta
	var w := p.weapons
	if _hint_t <= 0.0 and w.ammo[w.cur] + w.reserve[w.cur] == 0:
		_hint_t = 14.0
		Game.hud.show_message("Патроны кончились: подберите подсумок с убитого или идите к ящику (синяя метка на компасе)", 5.0)
	var lz := _obj("lz")
	if not lz.get("locked", false) and p.global_position.distance_to(lz.pos) < 7.0:
		lz.done = true
		finished = true
		Game.main.finish(true)


func _interact(delta: float, p: Player) -> void:
	var hud: Hud = Game.hud
	if p.vehicle != null:
		var cv := p.vehicle
		hud.prompt = "Выйти  |  %d км/ч  |  машина %d%%" % [int(absf(cv.speed) * 3.6), int(100.0 * cv.hp / cv.hp_max)]
		hud.prompt_progress = 0.0
		return
	var best := {}
	var best_d := 2.8
	var eye: Vector3 = p.aim_point()
	_veh_target = null
	var vd := 1.8
	for v in Game.vehicles:
		if not is_instance_valid(v) or not v.is_free():
			continue
		var rel: Vector3 = v.global_transform.affine_inverse() * p.global_position
		var bb: AABB = v.model.body_aabb
		var dx := maxf(absf(rel.x - bb.get_center().x) - bb.size.x * 0.5, 0.0)
		var dz := maxf(absf(rel.z - bb.get_center().z) - bb.size.z * 0.5, 0.0)
		var dd := Vector2(dx, dz).length()
		if dd < vd and absf(rel.y) < 2.5:
			vd = dd
			_veh_target = v
	if _veh_target:
		best = {"id": "veh", "prompt": "Сесть: " + _veh_target.display_name(), "hold": 0.3}
		best_d = 0.0
	for o in objectives:
		if o.done or o.armed or o.get("locked", false) or o.prompt == "":
			continue
		var d: float = eye.distance_to(o.pos)
		if d < best_d:
			best_d = d
			best = {"id": o.id, "prompt": o.prompt, "hold": o.hold}
	for a in Game.level.ammo_points:
		var d2: float = eye.distance_to(a)
		if d2 < best_d:
			best_d = d2
			best = {"id": "ammo", "prompt": "Пополнить боезапас", "hold": 1.0}
	if best.is_empty():
		hud.prompt = ""
		hud.prompt_progress = 0.0
		hold_t = 0.0
		hold_id = ""
		return
	if hold_id != best.id:
		hold_id = best.id
		hold_t = 0.0
	hud.prompt = best.prompt
	if p.in_interact:
		hold_t += delta
		if hold_t >= float(best.hold):
			hold_t = 0.0
			_done(String(best.id), p)
	else:
		hold_t = maxf(0.0, hold_t - delta * 2.0)
	hud.prompt_progress = hold_t / float(best.hold)


func _done(id: String, p: Player) -> void:
	var hud: Hud = Game.hud
	if id == "veh":
		if _veh_target and _veh_target.is_free():
			p.enter_vehicle(_veh_target)
		return
	if id == "ammo":
		p.weapons.refill()
		Sfx.play("mag_in", -3.0)
		hud.show_message("Боезапас пополнен")
		return
	var o := _obj(id)
	if id == "intel":
		o.done = true
		Game.level.destroy_objective("intel")
		Sfx.play("radio", -2.0)
		hud.show_message("Разведданные получены")
		_check_unlock()
		return
	o.armed = true
	charges.append({"id": id, "pos": o.pos, "t": 8.0, "beep": 0.0})
	Sfx.play("beep")
	hud.show_message("Заряд установлен — 8 секунд, в укрытие!", 4.0)


func _charges(delta: float) -> void:
	for c in charges:
		c.t -= delta
		c.beep -= delta
		if c.beep <= 0.0 and c.t > 0.0:
			c.beep = clampf(c.t * 0.14, 0.12, 1.0)
			Sfx.play_at("beep", c.pos, 0.0, 1.0, 6.0, 60.0)
		if c.t <= 0.0:
			_explode(String(c.id), c.pos)
	charges = charges.filter(func(c): return c.t > 0.0)


func _explode(id: String, pos: Vector3) -> void:
	var fx: Fx = Game.fx
	fx.explosion(pos, 15.0, 420.0)
	Game.level.destroy_objective(id)
	var extra: Dictionary = Game.level.blast_fx.get(id, {})
	for f in extra.get("fires", [[Vector3(0, 0.2, -1.5), 1.1]]):
		fx.fire(pos + (f[0] as Vector3), float(f[1]))
	for bl in extra.get("blasts", []):
		var at: Vector3 = pos + (bl[1] as Vector3)
		get_tree().create_timer(float(bl[0])).timeout.connect(func(): fx.explosion(at, 13.0, 300.0))
	var o := _obj(id)
	o.done = true
	Sfx.play("radio", -2.0)
	Game.hud.show_message("Цель уничтожена")
	_check_unlock()


func _check_unlock() -> void:
	for o in objectives:
		if o.id != "lz" and not o.done:
			return
	var lz := _obj("lz")
	lz.locked = false
	Game.fx.smoke_marker(lz.pos + Vector3(0, 0.2, 0), Color(0.3, 0.85, 0.35, 0.6))
	Game.hud.show_message("Все цели выполнены. Выходите к точке эвакуации — зелёный дым", 6.0)
