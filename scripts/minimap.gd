class_name MapView
extends Control
## Мини-карта (верхний левый угол, север вверху, окно 320 м вокруг игрока) и полная карта (тап по мини-карте или клавиша M).
## Картинка — assets/maps/<ключ>_map.res, печётся при `-- --bake` (Level.bake_map_image). Цели берутся из Mission.goals().
## Рисуется через UiBatch (атлас): картинка карты — отдельный вызов, остальное — пакетами.

const MINI := 150.0
const MINI_POS := Vector2(14, 14)
const WINDOW := 320.0

var hud: Hud
var open := false
var tex: Texture2D
var half := 600.0
var ub := UiBatch.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var lv: Level = Game.level
	if lv:
		half = lv.map_half()
		var path := Level.map_tex_path(lv.map_key)
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D


func mini_rect() -> Rect2:
	return Rect2(MINI_POS, Vector2(MINI, MINI))


## Касание попало в мини-карту (с запасом под палец).
func hit(pos: Vector2) -> bool:
	return mini_rect().grow(10.0).has_point(pos)


func toggle() -> void:
	open = not open
	Sfx.play("ui_click", -6.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and Game.playing:
		toggle()


static func label_of(g: Dictionary) -> String:
	return "Э" if g.lz else str(g.num)


func _draw() -> void:
	var p: Player = Game.player
	if p == null or p.dead or not Game.playing or Game.mission == null:
		return
	ub.begin(self, hud.font)
	if open:
		_draw_full(p)
	else:
		_draw_mini(p)
	ub.flush()


func _player_arrow(ctr: Vector2, b: float, k: float, col: Color) -> void:
	var s := sin(b)
	var c := cos(b)
	var pts := PackedVector2Array()
	for v in [Vector2(0, -8), Vector2(-5.5, 6), Vector2(0, 3), Vector2(5.5, 6)]:
		var q: Vector2 = v * k
		pts.append(ctr + Vector2(q.x * c - q.y * s, q.x * s + q.y * c))
	ub.draw_colored_polygon(pts, col)


func _badge(at: Vector2, r: float, g: Dictionary) -> void:
	var col := Color(1.0, 0.8, 0.25)
	if g.done:
		col = Color(0.45, 0.8, 0.4)
	elif g.lz:
		col = Color(0.4, 0.9, 0.45)
	ub.draw_circle(at, r + 1.5, Color(0, 0, 0, 0.7))
	ub.draw_circle(at, r, Color(col, 0.95))
	ub.text(at + Vector2(-20, r * 0.42), label_of(g), int(r * 1.5), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 40.0)


func _draw_mini(p: Player) -> void:
	var r := mini_rect()
	var cx := clampf(p.global_position.x, -half + WINDOW * 0.5, half - WINDOW * 0.5)
	var cz := clampf(p.global_position.z, -half + WINDOW * 0.5, half - WINDOW * 0.5)
	var x0 := cx - WINDOW * 0.5
	var z0 := cz - WINDOW * 0.5
	if tex != null:
		var ts := tex.get_size()
		var k := WINDOW / (half * 2.0)
		draw_texture_rect_region(tex, r, Rect2(Vector2((x0 + half) / (half * 2.0) * ts.x, (z0 + half) / (half * 2.0) * ts.y), ts * k), Color(1, 1, 1, 0.93))
	else:
		ub.draw_rect(r, Color(0.2, 0.22, 0.16, 0.8))
	var inner := r.grow(-8.0)
	for e in Game.enemies:
		if not is_instance_valid(e) or e.mark_t <= 0.0 or not e.alive():
			continue
		var q := r.position + Vector2((e.global_position.x - x0) / WINDOW, (e.global_position.z - z0) / WINDOW) * MINI
		if r.has_point(q):
			ub.draw_rect(Rect2(q - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.2, 0.15))
	for g in Game.mission.goals():
		if g.done or g.locked:
			continue
		var pos: Vector3 = g.pos
		var q := r.position + Vector2((pos.x - x0) / WINDOW, (pos.z - z0) / WINDOW) * MINI
		_badge(Vector2(clampf(q.x, inner.position.x, inner.end.x), clampf(q.y, inner.position.y, inner.end.y)), 7.0, g)
	var pq := r.position + Vector2((p.global_position.x - x0) / WINDOW, (p.global_position.z - z0) / WINDOW) * MINI
	_player_arrow(pq, -p.yaw, 1.0, Color(0.95, 0.95, 0.55))
	ub.draw_rect(r, Color(0, 0, 0, 0.85), false, 2.0)
	ub.text(r.position + Vector2(MINI * 0.5 - 10, 14), "С", 12, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 20.0)


func _draw_full(p: Player) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	var side := minf(size.y - 70.0, size.x - 40.0)
	var r := Rect2(Vector2(size.x * 0.5 - side * 0.5, 22.0), Vector2(side, side))
	if tex != null:
		draw_texture_rect(tex, r, false)
	else:
		ub.draw_rect(r, Color(0.2, 0.22, 0.16))
	var sc := Vector2(side, side) / (half * 2.0)
	var o := r.position + Vector2(half, half) * sc
	ub.draw_rect(r, Color(0, 0, 0, 0.9), false, 3.0)
	# ящики с боезапасом
	for a in Game.level.ammo_points:
		var q := o + Vector2((a as Vector3).x, (a as Vector3).z) * sc
		ub.draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), Color(0.45, 0.75, 1.0))
	for e in Game.enemies:
		if not is_instance_valid(e) or e.mark_t <= 0.0 or not e.alive():
			continue
		var q := o + Vector2(e.global_position.x, e.global_position.z) * sc
		ub.draw_circle(q, 3.5, Color(1.0, 0.2, 0.15))
	for g in Game.mission.goals():
		var pos: Vector3 = g.pos
		var q := o + Vector2(pos.x, pos.z) * sc
		if g.lz and g.locked:
			ub.draw_arc(q, 12.0, 0.0, TAU, 24, Color(0.4, 0.9, 0.45), 3.0)
			ub.text(q + Vector2(-20, 5), "Э", 15, Color(0.7, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
		else:
			_badge(q, 12.0, g)
		ub.text(q + Vector2(16, 5), String(g.title), 13, Color(1, 1, 1, 0.5 if g.done else 0.95))
	_player_arrow(o + Vector2(p.global_position.x, p.global_position.z) * sc, -p.yaw, 1.7, Color(0.95, 0.95, 0.55))
	ub.text(Vector2(r.position.x + side * 0.5 - 10, r.position.y + 20), "С", 16, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 20.0)
	ub.text(Vector2(0, size.y - 18), "КАРТА  ·  стрелка - вы, цифры - цели, Э - эвакуация, синие - боезапас  ·  M или касание - закрыть", 14, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)
