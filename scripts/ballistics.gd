class_name Ballistics
extends Node3D
## Пули как снаряды: скорость, гравитация, сопротивление воздуха, пробитие тонких преград.

class Bullet:
	var pos: Vector3
	var vel: Vector3
	var dmg: float
	var shooter: Node
	var from_player: bool
	var origin: Vector3
	var life := 0.0
	var drag := 0.25
	var pen := 1
	var whizzed := false
	var tracer: MeshInstance3D
	var tracer_off := Vector3.ZERO
	var travelled := 0.0

const GRAVITY := 9.81

var bullets: Array[Bullet] = []
var _tracers: Array[MeshInstance3D] = []
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 7.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.78, 0.35)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	for i in 16:
		var t := MeshInstance3D.new()
		t.mesh = mesh
		t.material_override = mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		_tracers.append(t)


func fire(origin: Vector3, dir: Vector3, speed: float, dmg: float, shooter: Node, from_player: bool,
		tracer := false, visual_origin := Vector3.INF, drag := 0.25) -> void:
	var b := Bullet.new()
	b.pos = origin
	b.origin = origin
	b.vel = dir * speed
	b.dmg = dmg
	b.shooter = shooter
	b.from_player = from_player
	b.drag = drag
	if tracer:
		for t in _tracers:
			if not t.visible:
				b.tracer = t
				b.tracer_off = (visual_origin - origin) if visual_origin != Vector3.INF else Vector3.ZERO
				break
	if not _step(b, 1.0 / 60.0):
		bullets.append(b)
		if b.tracer:
			_place_tracer(b)
			b.tracer.visible = true
			b.tracer.reset_physics_interpolation()
	elif b.tracer:
		b.tracer.visible = false


func _physics_process(delta: float) -> void:
	var i := bullets.size() - 1
	while i >= 0:
		var b := bullets[i]
		if _step(b, delta):
			if b.tracer:
				b.tracer.visible = false
			bullets.remove_at(i)
		elif b.tracer:
			_place_tracer(b)
		i -= 1


func _place_tracer(b: Bullet) -> void:
	var dir := b.vel.normalized()
	var k := clampf(1.0 - b.travelled / 30.0, 0.0, 1.0)
	var p := b.pos + b.tracer_off * k - dir * 3.5
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	b.tracer.global_transform = Transform3D(Basis.looking_at(dir, up), p)


## Продвигает пулю на dt. Возвращает true, если пуля закончила полёт.
func _step(b: Bullet, dt: float) -> bool:
	var space := get_world_3d().direct_space_state
	b.vel.y -= GRAVITY * dt
	b.vel *= maxf(0.0, 1.0 - b.drag * dt)
	var from := b.pos
	var to := from + b.vel * dt
	var dir := b.vel.normalized()
	var guard := 3
	_query.collision_mask = Game.L_WORLD | (Game.L_ENEMY if b.from_player else Game.L_PLAYER)
	while guard > 0:
		guard -= 1
		_query.from = from
		_query.to = to
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			break
		var col: Object = hit.collider
		var hp: Vector3 = hit.position
		if col is Enemy:
			var res: Dictionary = (col as Enemy).take_hit(b.dmg, hp, dir, b.origin)
			if b.from_player and Game.player and not res.is_empty():
				Game.player.on_hit_enemy(res, b.origin.distance_to(hp))
			return true
		if col == Game.player:
			Game.player.take_damage(b.dmg, b.origin)
			return true
		if col is Vehicle:
			(col as Vehicle).take_hit(b.dmg, hp, b.from_player)
		var surf: String = col.get_meta("surf", "concrete")
		Game.fx.impact(hp, hit.normal, surf, dir)
		if (surf == "wood" or surf == "sheet") and b.pen > 0 and b.dmg > 12.0:
			b.pen -= 1
			b.dmg *= 0.55
			from = hp + dir * 0.3
			if (from - b.pos).length() >= (to - b.pos).length():
				to = from + dir * 0.6
			continue
		return true
	_near_miss(b, b.pos, to)
	b.travelled += (to - b.pos).length()
	b.pos = to
	b.life += dt
	return b.life > 3.0 or b.pos.y < -80.0


func _near_miss(b: Bullet, a: Vector3, c: Vector3) -> void:
	if b.whizzed:
		return
	if b.from_player:
		for e in Game.enemies:
			if is_instance_valid(e) and e.alive():
				var p: Vector3 = e.global_position + Vector3(0, 1.2, 0)
				var q := Geometry3D.get_closest_point_to_segment(p, a, c)
				if q.distance_to(p) < 2.2 and q != a and q != c:
					e.suppressed(b.origin)
	elif Game.player and not Game.player.dead:
		var head: Vector3 = Game.player.aim_point()
		var q2 := Geometry3D.get_closest_point_to_segment(head, a, c)
		if q2.distance_to(head) < 2.4 and q2 != c:
			b.whizzed = true
			Sfx.play_at("whizz%d" % (randi() % 2), q2, 0.0, randf_range(0.9, 1.15), 4.0, 40.0)
			Game.player.suppress(0.35)
