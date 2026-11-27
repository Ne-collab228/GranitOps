class_name TouchControls
extends Control
## Сенсорное управление: плавающий джойстик слева, обзор свайпом справа, кнопки действий.
## Палец на кнопке огня одновременно ведёт прицел.

# id, привязка (0 — слева, 1 — справа, 2 — от центра), смещение X, смещение Y от низа (<0 — от верха), радиус
const BTN := [
	["fire", 1, 172.0, 186.0, 66.0],
	["ads", 1, 64.0, 266.0, 44.0],
	["jump", 1, 64.0, 134.0, 44.0],
	["crouch", 1, 178.0, 62.0, 38.0],
	["reload", 1, 298.0, 128.0, 38.0],
	["switch", 1, 302.0, 232.0, 36.0],
	["grenade", 1, 216.0, 322.0, 33.0],
	["heal", 1, 118.0, 366.0, 31.0],
	["mode", 1, 392.0, 150.0, 28.0],
	["fire2", 0, 74.0, 344.0, 46.0],
	["pause", 1, 46.0, -46.0, 26.0],
	["interact", 2, 215.0, 70.0, 48.0],
	["thermal", 2, -300.0, 150.0, 30.0],
]
const STICK_R := 82.0

var hud: Hud
var fingers := {}
var move_finger := -1
var move_origin := Vector2.ZERO
var look_finger := -1
var stick := Vector2.ZERO
var sprint_latch := false


## Своё расположение кнопки из настроек (редактор TouchLayoutEditor) или пустой массив.
static func layout_of(id: String) -> Array:
	var lay = Settings.data.get("btn_layout", {})
	if lay is Dictionary and (lay as Dictionary).has(id):
		var l = lay[id]
		if l is Array and (l as Array).size() >= 3:
			var x := float(l[0])
			var y := float(l[1])
			var sc := float(l[2])
			# испорченные значения (NaN, за экраном) — как будто расположение не задано
			if is_finite(x) and is_finite(y) and is_finite(sc) and x >= 0.0 and x <= 1.0 and y >= 0.0 and y <= 1.0 and sc > 0.3 and sc < 3.0:
				return l
	return []


static func btn_r(b: Array) -> float:
	var l := layout_of(String(b[0]))
	return float(b[4]) * (float(l[2]) if not l.is_empty() else 1.0)


static func btn_pos_for(b: Array, s: Vector2) -> Vector2:
	var l := layout_of(String(b[0]))
	if not l.is_empty():
		return Vector2(float(l[0]) * s.x, float(l[1]) * s.y)
	return default_pos(b, s)


static func default_pos(b: Array, s: Vector2) -> Vector2:
	var y: float = (s.y - float(b[3])) if float(b[3]) >= 0.0 else -float(b[3])
	match int(b[1]):
		0:
			return Vector2(float(b[2]), y)
		1:
			return Vector2(s.x - float(b[2]), y)
	return Vector2(s.x * 0.5 + float(b[2]), s.y * 0.5 + float(b[3]))


## Джойстик: место в покое и радиус (масштаб из редактора).
static func stick_rest(s: Vector2) -> Vector2:
	var l := layout_of("stick")
	return Vector2(float(l[0]) * s.x, float(l[1]) * s.y) if not l.is_empty() else Vector2(160.0, s.y - 175.0)


static func stick_r() -> float:
	var l := layout_of("stick")
	return STICK_R * (float(l[2]) if not l.is_empty() else 1.0)


func _btn_pos(b: Array) -> Vector2:
	return btn_pos_for(b, size)


func _btn_visible(id: String) -> bool:
	var p: Player = Game.player
	if p != null and p.vehicle != null:
		return id == "interact" or id == "pause"
	match id:
		"fire2":
			return bool(Settings.data.left_fire)
		"interact":
			return hud.prompt != ""
		"mode":
			return p != null and bool(p.weapons.def().auto)
		"thermal":
			return p != null and p.weapons.scoped and String(p.weapons.def().get("optic", "")) == "thermal"
	return true


func _input(event: InputEvent) -> void:
	if not Game.playing or Game.player == null or Game.player.dead:
		if not fingers.is_empty():
			_release_all()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_down(event.index, event.position)
		else:
			_up(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)


func _down(i: int, pos: Vector2) -> void:
	var p: Player = Game.player
	# карта: тап по мини-карте открывает/закрывает полную, на открытой карте любой тап её закрывает
	if hud.map != null and (hud.map.open or hud.map.hit(pos)):
		hud.map.toggle()
		return
	for b in BTN:
		var id: String = b[0]
		if not _btn_visible(id):
			continue
		if pos.distance_to(_btn_pos(b)) <= btn_r(b) * 1.2:
			fingers[i] = id
			match id:
				"fire", "fire2":
					p.t_fire = true
				"ads":
					p.t_ads = (not p.t_ads) if Settings.data.toggle_ads else true
				"interact":
					p.t_interact = true
				"pause":
					Game.main.toggle_pause()
				"switch":
					p.act("next_weapon")
				"mode":
					p.act("firemode")
				"thermal":
					Settings.data.thermal_bh = not bool(Settings.data.get("thermal_bh", false))
					Sfx.play("ui_click", -6.0)
				_:
					p.act(id)
			return
	# зона джойстика: левые 42% экрана; если джойстик перенесли — полоса той же ширины вокруг него
	var in_stick := pos.x < size.x * 0.42
	if not layout_of("stick").is_empty():
		in_stick = absf(pos.x - stick_rest(size).x) < maxf(size.x * 0.21, stick_r() * 1.6)
	if in_stick and move_finger < 0:
		move_finger = i
		move_origin = pos
		fingers[i] = "move"
	elif look_finger < 0:
		look_finger = i
		fingers[i] = "look"


func _drag(i: int, pos: Vector2, rel: Vector2) -> void:
	var p: Player = Game.player
	var role: String = fingers.get(i, "")
	if role == "move":
		var sr := stick_r()
		var v := (pos - move_origin) / sr
		if v.length() > 1.25:
			move_origin += v.normalized() * (v.length() - 1.25) * sr
			v = (pos - move_origin) / sr
		stick = v.limit_length(1.0)
		p.t_move = Vector2(stick.x, -stick.y) if stick.length() > 0.14 else Vector2.ZERO
		# бег включается толчком стика до упора вперёд и держится, пока стик смотрит вперёд
		if v.length() > 0.93 and stick.y < -0.72:
			sprint_latch = true
		elif stick.y > -0.4 or stick.length() < 0.55:
			sprint_latch = false
		p.t_sprint = sprint_latch
	elif role == "look" or role == "fire" or role == "fire2" or role == "ads":
		p.look_touch(rel)


func _up(i: int) -> void:
	var p: Player = Game.player
	var role: String = fingers.get(i, "")
	fingers.erase(i)
	match role:
		"move":
			move_finger = -1
			stick = Vector2.ZERO
			sprint_latch = false
			p.t_move = Vector2.ZERO
			p.t_sprint = false
		"look":
			look_finger = -1
		"fire", "fire2":
			p.t_fire = fingers.values().has("fire") or fingers.values().has("fire2")
		"interact":
			p.t_interact = false
		"ads":
			if not Settings.data.toggle_ads:
				p.t_ads = false


func _release_all() -> void:
	fingers.clear()
	move_finger = -1
	look_finger = -1
	stick = Vector2.ZERO
	sprint_latch = false
	var p: Player = Game.player
	if p:
		p.t_move = Vector2.ZERO
		p.t_fire = false
		p.t_sprint = false
		p.t_interact = false


var ub := UiBatch.new()


func _draw() -> void:
	var p: Player = Game.player
	if p == null or p.dead or not Game.playing:
		return
	ub.begin(self, hud.font)
	modulate.a = clampf(float(Settings.data.get("btn_alpha", 1.0)), 0.2, 1.0)
	var line := Color(1, 1, 1, 0.6)
	# джойстик
	var sr := stick_r()
	var base := move_origin if move_finger >= 0 else stick_rest(size)
	ub.draw_circle(base, sr, Color(0, 0, 0, 0.14 if move_finger >= 0 else 0.07))
	ub.draw_arc(base, sr, 0.0, TAU, 40, Color(1, 1, 1, 0.4 if move_finger >= 0 else 0.18), 2.0)
	ub.draw_circle(base + stick * sr, 30.0 * sr / STICK_R, Color(1, 1, 1, 0.32 if move_finger >= 0 else 0.12))
	if p.sprinting:
		ub.draw_arc(base, sr + 8.0, -PI * 0.75, -PI * 0.25, 12, Color(1.0, 0.85, 0.4, 0.8), 4.0)
	for b in BTN:
		var id: String = b[0]
		if not _btn_visible(id):
			continue
		var c := _btn_pos(b)
		var r := btn_r(b)
		var on: bool = fingers.values().has(id) or (id == "ads" and p.t_ads) or (id == "crouch" and p.crouching)
		ub.draw_circle(c, r, Color(1, 1, 1, 0.2) if on else Color(0, 0, 0, 0.2))
		ub.draw_arc(c, r, 0.0, TAU, 36, Color(1.0, 0.86, 0.5, 0.9) if on else line, 2.0)
		var col := Color(1, 1, 1, 0.92)
		ub.icon(id, c, r, col)
		# текст на кнопках меняется — не в атласе
		match id:
			"grenade":
				ub.text(c + Vector2(r * 0.45, -r * 0.5), str(p.weapons.grenades), 15, Color(1.0, 0.9, 0.6))
			"heal":
				ub.text(c + Vector2(r * 0.5, -r * 0.5), str(p.weapons.medkits), 15, Color(1.0, 0.9, 0.6))
			"mode":
				ub.text(c + Vector2(-r, 5), "ОДН" if p.weapons.semi[p.weapons.cur] else "АВТ", 13, col, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
			"thermal":
				ub.text(c + Vector2(-r, 5), "ЧГ" if bool(Settings.data.get("thermal_bh", false)) else "БГ", 13, col, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
			"interact":
				if hud.prompt_progress > 0.0:
					ub.draw_arc(c, r + 6.0, -PI * 0.5, -PI * 0.5 + TAU * hud.prompt_progress, 40, Color(1.0, 0.86, 0.5), 5.0)
	ub.flush()


## Значок кнопки (только фигуры, без текста): s — масштаб (радиус кнопки / 40), wm — множитель толщины линий.
## Вызывается и напрямую, и один раз для атласа UiBatch.
static func paint_icon(t: CanvasItem, id: String, c: Vector2, s: float, col: Color, wm := 1.0) -> void:
	match id:
		"fire", "fire2":
			t.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -6) * s, c + Vector2(0, -24) * s, c + Vector2(7, -6) * s]), col)
			t.draw_rect(Rect2(c + Vector2(-7, -6) * s, Vector2(14, 22) * s), col)
			t.draw_rect(Rect2(c + Vector2(-9, 18) * s, Vector2(18, 4) * s), col)
		"ads":
			t.draw_arc(c, 15.0 * s, 0.0, TAU, 32, col, 2.5 * wm, true)
			t.draw_line(c - Vector2(22, 0) * s, c + Vector2(22, 0) * s, col, 2.0 * wm)
			t.draw_line(c - Vector2(0, 22) * s, c + Vector2(0, 22) * s, col, 2.0 * wm)
		"jump":
			for o in [-4.0, 8.0]:
				t.draw_polyline(PackedVector2Array([c + Vector2(-13, o + 4) * s, c + Vector2(0, o - 9) * s, c + Vector2(13, o + 4) * s]), col, 3.5 * wm, true)
		"crouch":
			for o in [-8.0, 4.0]:
				t.draw_polyline(PackedVector2Array([c + Vector2(-13, o - 4) * s, c + Vector2(0, o + 9) * s, c + Vector2(13, o - 4) * s]), col, 3.5 * wm, true)
		"reload":
			t.draw_arc(c, 14.0 * s, -PI * 0.35, PI * 1.25, 32, col, 3.5 * wm, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * 14.0 * s
			t.draw_colored_polygon(PackedVector2Array([tip + Vector2(-8, -7) * s, tip + Vector2(7, -3) * s, tip + Vector2(-3, 8) * s]), col)
		"switch":
			t.draw_line(c + Vector2(-14, -6) * s, c + Vector2(14, -6) * s, col, 3.0 * wm)
			t.draw_colored_polygon(PackedVector2Array([c + Vector2(14, -13) * s, c + Vector2(22, -6) * s, c + Vector2(14, 1) * s]), col)
			t.draw_line(c + Vector2(-14, 8) * s, c + Vector2(14, 8) * s, col, 3.0 * wm)
			t.draw_colored_polygon(PackedVector2Array([c + Vector2(-14, 1) * s, c + Vector2(-22, 8) * s, c + Vector2(-14, 15) * s]), col)
		"grenade":
			t.draw_circle(c + Vector2(0, 4) * s, 13.0 * s, col)
			t.draw_rect(Rect2(c + Vector2(-5, -18) * s, Vector2(10, 8) * s), col)
		"heal":
			t.draw_rect(Rect2(c + Vector2(-5, -15) * s, Vector2(10, 30) * s), col)
			t.draw_rect(Rect2(c + Vector2(-15, -5) * s, Vector2(30, 10) * s), col)
		"pause":
			t.draw_rect(Rect2(c + Vector2(-9, -11) * s, Vector2(6, 22) * s), col)
			t.draw_rect(Rect2(c + Vector2(3, -11) * s, Vector2(6, 22) * s), col)
		"interact":
			t.draw_circle(c, 13.0 * s, col)
