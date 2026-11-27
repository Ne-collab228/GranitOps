class_name Hud
extends CanvasLayer
## Интерфейс в бою: прицел, компас, боезапас, здоровье, задачи, оптика.

class Canvas extends Control:
	var hud: Hud
	func _draw() -> void:
		hud.draw_hud(self)

const SCOPE_SHADER := "
shader_type canvas_item;
// Оптический прицел: линза с бочкообразным искажением и хроматической аберрацией у края,
// тень выходного зрачка (смещается при качании), затемнение к краю, блик просветления.
// thermal = 1: монохромная картинка тепловизора (размытие, шум матрицы, строки развёртки).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float aspect = 1.777;
uniform float radius = 0.45;
uniform vec2 offset = vec2(0.0);
uniform float thermal = 0.0;
uniform float black_hot = 0.0;
uniform float time = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 q = SCREEN_UV - 0.5;
	vec2 p = q * vec2(aspect, 1.0);
	float d = length(p);
	float r = d / radius;
	float lens = 1.0 - smoothstep(radius - 0.003, radius + 0.003, d);
	float eye = 1.0 - smoothstep(radius * 0.8, radius * 1.04, length(p - offset));
	float k = 0.07 * r * r;
	vec3 col;
	if (thermal > 0.5) {
		vec2 uv = 0.5 + q * (1.0 - k);
		vec2 px = SCREEN_PIXEL_SIZE * 1.6;
		vec3 s = texture(screen_tex, uv).rgb * 0.4;
		s += texture(screen_tex, uv + vec2(px.x, 0.0)).rgb * 0.15;
		s += texture(screen_tex, uv - vec2(px.x, 0.0)).rgb * 0.15;
		s += texture(screen_tex, uv + vec2(0.0, px.y)).rgb * 0.15;
		s += texture(screen_tex, uv - vec2(0.0, px.y)).rgb * 0.15;
		float h = dot(s, vec3(0.3, 0.59, 0.11));
		h = clamp((h - 0.06) * 1.25, 0.0, 1.0);
		h = h * h * (3.0 - 2.0 * h);
		h = mix(h, 1.0 - h, black_hot);
		h += (hash(floor(SCREEN_UV / SCREEN_PIXEL_SIZE / 2.0) + fract(time * 7.0) * 91.0) - 0.5) * 0.07;
		h *= 0.96 + 0.04 * sin(SCREEN_UV.y / SCREEN_PIXEL_SIZE.y * 1.6);
		col = vec3(h) * vec3(0.96, 1.0, 0.97);
	} else {
		vec3 c;
		c.r = texture(screen_tex, 0.5 + q * (1.0 - k * 1.04)).r;
		c.g = texture(screen_tex, 0.5 + q * (1.0 - k)).g;
		c.b = texture(screen_tex, 0.5 + q * (1.0 - k * 0.96)).b;
		col = c * vec3(0.96, 0.99, 1.0);
	}
	col *= 1.0 - 0.38 * smoothstep(0.5, 1.0, r);
	vec2 dir = d > 0.0001 ? p / d : vec2(0.0);
	col += vec3(0.35, 0.55, 0.7) * smoothstep(0.86, 1.0, r) * max(0.0, dot(dir, vec2(-0.6, -0.8))) * 0.22;
	COLOR = vec4(col * lens * eye, 1.0);
}"
const VIGNETTE_SHADER := "
shader_type canvas_item;
uniform float dmg = 0.0;
uniform float low = 0.0;
uniform float dark = 0.2;
void fragment() {
	vec2 p = UV - 0.5;
	float v = smoothstep(0.22, 0.95, dot(p, p) * 2.3);
	vec3 col = mix(vec3(0.0), vec3(0.5, 0.0, 0.0), clamp(dmg + low * 0.7, 0.0, 1.0));
	COLOR = vec4(col, v * clamp(dark + dmg * 0.8 + low * 0.4, 0.0, 1.0));
}"

var canvas: Canvas
var scope_rect: ColorRect
var vignette: ColorRect
var touch: TouchControls
var map: MapView
var font: Font

var hit_t := 0.0
var hit_kill := false
var hit_head := false
var dmg_marks: Array = []
var dmg_flash := 0.0
var message := ""
var message_t := 0.0
var prompt := ""
var prompt_progress := 0.0


func _ready() -> void:
	layer = 5
	font = UiBatch.hud_font()
	UiBatch.ensure(self)
	vignette = _shader_rect(VIGNETTE_SHADER)
	scope_rect = _shader_rect(SCOPE_SHADER)
	scope_rect.visible = false
	canvas = Canvas.new()
	canvas.hud = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# атлас интерфейса уменьшается в разы (кружок 120 px → точка 3 px) — нужны мипмапы
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(canvas)
	map = MapView.new()
	map.hud = self
	add_child(map)
	if "--mapshot" in OS.get_cmdline_user_args():
		_mapshot()
	if Settings.touch_ui:
		touch = TouchControls.new()
		touch.hud = self
		touch.set_anchors_preset(Control.PRESET_FULL_RECT)
		touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		touch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(touch)


func _shader_rect(code: String) -> ColorRect:
	var r := ColorRect.new()
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func hit_marker(killed: bool, head: bool) -> void:
	hit_t = 0.3 if killed else 0.2
	hit_kill = killed
	hit_head = head


func damage_from(angle: float) -> void:
	dmg_marks.append([angle, 1.3])
	dmg_flash = 0.7


func show_message(text: String, time := 3.5) -> void:
	message = text
	message_t = time


func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	dmg_flash = maxf(0.0, dmg_flash - delta * 1.6)
	message_t = maxf(0.0, message_t - delta)
	for m in dmg_marks:
		m[1] -= delta
	dmg_marks = dmg_marks.filter(func(m): return m[1] > 0.0)
	var p: Player = Game.player
	if p:
		var vm := vignette.material as ShaderMaterial
		vm.set_shader_parameter("dmg", dmg_flash)
		vm.set_shader_parameter("low", clampf((40.0 - p.hp) / 40.0, 0.0, 1.0))
		vm.set_shader_parameter("dark", 0.18 + p.suppression * 0.5)
		var was_scoped := scope_rect.visible
		scope_rect.visible = p.weapons.scoped and not p.dead and p.vehicle == null
		if was_scoped != scope_rect.visible:
			Blackbox.event(("прицел " + String(p.weapons.def().get("optic", ""))) if scope_rect.visible else "прицел выкл")
		var th := scope_rect.visible and String(p.weapons.def().get("optic", "")) == "thermal"
		if th != Mats.thermal_on:
			Mats.set_thermal(th)
			if Game.level:
				Game.level.set_thermal(th)
		if scope_rect.visible:
			var sm := scope_rect.material as ShaderMaterial
			sm.set_shader_parameter("aspect", canvas.size.x / maxf(1.0, canvas.size.y))
			sm.set_shader_parameter("thermal", 1.0 if th else 0.0)
			sm.set_shader_parameter("black_hot", 1.0 if bool(Settings.data.get("thermal_bh", false)) else 0.0)
			sm.set_shader_parameter("time", Time.get_ticks_msec() * 0.001)
			# тень выходного зрачка: качание оружия, ходьба и момент вскидывания
			var w: Weapons = p.weapons
			var settle := 1.0 - smoothstep(0.82, 1.0, w.ads)
			var vel := Vector2(p.velocity.x, p.velocity.z).length()
			var bob := Vector2(sin(w.time * 7.0), absf(cos(w.time * 7.0))) * clampf(vel / 5.0, 0.0, 1.0) * 0.03
			sm.set_shader_parameter("offset", Vector2(w.sway.x * 4.0, -w.sway.y * 4.0) + bob + Vector2(0.0, settle * 0.3))
	canvas.queue_redraw()
	map.queue_redraw()
	if touch:
		touch.visible = not map.open
		touch.queue_redraw()


func text(c: Control, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if c == canvas:
		ub.text(pos, s, size, col, align, width)
		return
	c.draw_string_outline(font, pos, s, align, width, size, 8 if UiBatch.is_msdf(font) else 4, Color(0, 0, 0, 0.75 * col.a))
	c.draw_string(font, pos, s, align, width, size, col)


var ub := UiBatch.new()


## Отладка (-- --play --mapshot [--touch]): снимки интерфейса навигации и замер вызовов отрисовки.
func _mapshot() -> void:
	for i in 120:
		await get_tree().process_frame
	var p: Player = Game.player
	var key: String = Game.level.map_key
	var draws := func() -> float:
		var d := 0.0
		for i in 20:
			await get_tree().process_frame
			d += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		return d / 20.0
	var d_on: float = await draws.call()
	map.visible = false
	var d_off: float = await draws.call()
	map.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	print("MAPSHOT draw с картой/списком: %.1f, без карты: %.1f" % [d_on, d_off])
	get_viewport().get_texture().get_image().save_png("user://test_map_%s_hud.png" % key)
	p.yaw += 2.2
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://test_map_%s_edge.png" % key)
	Game.mission.objectives[0].done = true
	map.toggle()
	for i in 10:
		await get_tree().process_frame
	print("MAPSHOT draw полная карта: %.1f" % await draws.call())
	get_viewport().get_texture().get_image().save_png("user://test_map_%s_full.png" % key)
	get_tree().quit()


## Список задач слева под мини-картой (не доходит до сенсорных кнопок: они ниже 350 px).
func _goal_list(c: Control, p: Player, mis: Mission) -> void:
	var y := MapView.MINI_POS.y + MapView.MINI + 26.0
	text(c, Vector2(16, y), "ЗАДАЧИ", 13, Color(0.93, 0.86, 0.68))
	for g in mis.goals():
		y += 21.0
		var done: bool = g.done
		var locked: bool = g.locked
		var col := Color(0.55, 0.9, 0.5, 0.9) if done else (Color(1, 1, 1, 0.4) if locked else Color(1, 1, 1, 0.95))
		var bc := Color(0.45, 0.8, 0.4, 0.8) if done else (Color(0.5, 0.5, 0.5, 0.6) if locked else Color(1.0, 0.8, 0.25, 0.95))
		ub.draw_circle(Vector2(24, y - 5.0), 8.5, bc)
		text(c, Vector2(4, y - 0.5), MapView.label_of(g), 11, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
		var t: String = g.title
		if t.length() > 30:
			t = t.substr(0, 28) + ".."
		text(c, Vector2(38, y), t, 13, col)
		if not done and not locked:
			var d: float = Vector2((g.pos as Vector3).x - p.global_position.x, (g.pos as Vector3).z - p.global_position.z).length()
			text(c, Vector2(198, y), "%d м" % int(d), 12, Color(1.0, 0.8, 0.25), HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
		elif done:
			text(c, Vector2(198, y), "готово", 12, col, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)


## Номера и расстояния над целями; цель вне экрана — значок у края с цепочкой точек-стрелкой. Выполненные не рисуются.
func _goal_marks(c: Control, p: Player, mis: Mission) -> void:
	if p.dead:
		return
	var cam := p.cam
	var sz := c.size
	var ctr := sz * 0.5
	var k := sz / Vector2(c.get_viewport_rect().size)
	var inv := cam.global_transform.affine_inverse()
	var placed: Array = []
	for g in mis.goals():
		if g.done or g.locked:
			continue
		var wp: Vector3 = (g.pos as Vector3) + Vector3(0, 2.5, 0)
		var dist: float = cam.global_position.distance_to(g.pos)
		var sp: Vector2 = cam.unproject_position(wp) * k
		var inside := not cam.is_position_behind(wp) and sp.is_finite() and sp.x > 40.0 and sp.x < sz.x - 40.0 and sp.y > 90.0 and sp.y < sz.y - 70.0
		var col := Color(0.4, 0.9, 0.45) if g.lz else Color(1.0, 0.8, 0.25)
		var at := sp
		if not inside:
			var lp: Vector3 = inv * wp
			var dir := Vector2(lp.x, -lp.y)
			if dir.length() < 0.001:
				dir = Vector2(0, 1)
			dir = dir.normalized()
			if absf(lp.x) < 0.001 and lp.z > 0.0 and absf(lp.y) < 0.001:
				dir = Vector2(0, 1)
			var sx := (ctr.x - 50.0) / maxf(absf(dir.x), 0.0001)
			var sy := (ctr.y - 90.0) / maxf(absf(dir.y), 0.0001)
			at = ctr + dir * minf(sx, sy)
			if at.x < 330.0 and at.y < 350.0:
				at.y = 350.0
			# значки у края не налезают друг на друга
			var base_at := at
			for off in [0.0, 46.0, -46.0, 92.0, -92.0, 138.0, -138.0]:
				var cand := base_at + Vector2(0, off)
				if cand.y < 100.0 or cand.y > sz.y - 90.0:
					continue
				var clash := false
				for q in placed:
					if (q as Vector2).distance_to(cand) < 42.0:
						clash = true
				if not clash:
					at = cand
					break
			placed.append(at)
			for i in 2:
				ub.draw_circle(at + dir * (22.0 + i * 9.0), 4.0 - i * 1.4, Color(col, 0.9))
		ub.draw_circle(at, 14.0, Color(0, 0, 0, 0.55))
		ub.draw_arc(at, 14.0, 0.0, TAU, 24, col, 2.0)
		text(c, at + Vector2(-20, 6), MapView.label_of(g), 16, Color(1, 1, 1, 0.97), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
		text(c, at + Vector2(-40, 31), "%d м" % int(dist), 12, col, HORIZONTAL_ALIGNMENT_CENTER, 80.0)


func draw_hud(c: Control) -> void:
	var p: Player = Game.player
	if p == null or not Game.playing and not p.dead:
		return
	ub.begin(c, font)
	_draw_hud(c, p)
	ub.flush()


func _draw_hud(c: Control, p: Player) -> void:
	var w: Weapons = p.weapons
	var sz := c.size
	var ctr := sz * 0.5
	var d := w.def()
	var white := Color(1, 1, 1, 0.9)
	var sand := Color(0.93, 0.86, 0.68)

	# --- метки обнаруженных противников
	if Settings.data.marks and not p.dead:
		var cam := p.cam
		var red := Color(1.0, 0.22, 0.16)
		for e in Game.enemies:
			if not is_instance_valid(e) or e.mark_t <= 0.0 or not e.alive():
				continue
			var hp3: Vector3 = e.global_position + Vector3(0, 2.05 - 0.55 * e.crouch, 0)
			if cam.is_position_behind(hp3):
				continue
			var sp: Vector2 = cam.unproject_position(hp3) * (sz / Vector2(c.get_viewport_rect().size))
			if not sp.is_finite() or sp.x < -50.0 or sp.y < -50.0 or sp.x > sz.x + 50.0 or sp.y > sz.y + 50.0:
				continue
			var al := clampf(e.mark_t, 0.0, 1.0) * 0.95
			var dist: float = cam.global_position.distance_to(hp3)
			var k := 1.0 if dist > 25.0 else 0.75
			ub.tri(Rect2(sp.x - 7.0 * k, sp.y - 13.0 * k, 14.0 * k, 13.0 * k - 2.0), Color(red, al), true, Color(0, 0, 0, al * 0.7))
			if dist > 35.0:
				text(c, sp + Vector2(-30, -17), "%d" % int(dist), 11, Color(1, 0.8, 0.75, al), HORIZONTAL_ALIGNMENT_CENTER, 60.0)

	# --- оптика / прицел
	var optic: String = d.get("optic", "iron")
	if w.scoped:
		var black := Color(0, 0, 0, 0.9)
		var rad := sz.y * 0.44
		var mil := sz.y / (p.cam.fov * 17.45)
		if optic == "thermal":
			# сетка тепловизора: тонкое перекрестие с разрывом, дальномерные штрихи, служебные надписи
			var bh := bool(Settings.data.get("thermal_bh", false))
			var tc := Color(0.05, 0.05, 0.05, 0.95) if bh else Color(0.95, 1.0, 0.95, 0.95)
			for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ub.draw_line(ctr + v * 10.0, ctr + v * rad * 0.85, tc, 1.3)
			ub.draw_circle(ctr, 1.6, tc)
			for i in range(1, 6):
				var yy := ctr.y + i * 4.0 * mil
				ub.draw_line(Vector2(ctr.x - 6.0 + i, yy), Vector2(ctr.x + 6.0 - i, yy), tc, 1.2)
			for sgn in [-1.0, 1.0]:
				for i in range(1, 5):
					ub.draw_line(ctr + Vector2(sgn * i * 5.0 * mil, -4), ctr + Vector2(sgn * i * 5.0 * mil, 4), tc, 1.2)
			var tl := ctr + Vector2(-rad * 0.62, -rad * 0.6)
			text(c, tl, "ЧГ" if bh else "БГ", 15, tc)
			text(c, tl + Vector2(0, 20), "x4", 15, tc)
			var br := ctr + Vector2(rad * 0.42, rad * 0.62)
			ub.draw_rect(Rect2(br, Vector2(26, 11)), tc, false, 1.2)
			ub.draw_rect(Rect2(br + Vector2(26, 3), Vector2(3, 5)), tc)
			ub.draw_rect(Rect2(br + Vector2(2, 2), Vector2(16, 7)), tc)
		elif optic == "x10":
			# тонкая сетка снайперского прицела: толстые «пеньки» к краю, мил-штрихи, точка подсветки
			ub.draw_line(ctr - Vector2(rad * 0.5, 0), ctr + Vector2(rad * 0.5, 0), black, 1.0)
			ub.draw_line(ctr - Vector2(0, rad * 0.5), ctr + Vector2(0, rad * 0.5), black, 1.0)
			for sgn in [-1.0, 1.0]:
				ub.draw_line(ctr + Vector2(sgn * rad * 0.5, 0), ctr + Vector2(sgn * rad, 0), black, 5.0)
				ub.draw_line(ctr + Vector2(0, sgn * rad * 0.5), ctr + Vector2(0, sgn * rad), black, 5.0)
				for i in range(1, 11):
					var l := 6.0 if i % 5 == 0 else 3.0
					ub.draw_line(ctr + Vector2(sgn * i * mil, -l), ctr + Vector2(sgn * i * mil, l), black, 1.0)
			for i in range(1, 11):
				var l2 := 6.0 if i % 5 == 0 else 3.0
				ub.draw_line(ctr + Vector2(-l2, i * mil), ctr + Vector2(l2, i * mil), black, 1.0)
			ub.draw_circle(ctr, 1.5, Color(1.0, 0.15, 0.1, 0.9))
		elif optic == "x3":
			# сетка «шеврон» с дальномерными штрихами
			var redc := Color(1.0, 0.16, 0.1, 0.95)
			ub.draw_polyline(PackedVector2Array([ctr + Vector2(-9, 11), ctr, ctr + Vector2(9, 11)]), redc, 2.2)
			for i in range(1, 5):
				var wd := 16.0 - i * 2.5
				ub.draw_line(ctr + Vector2(-wd, i * 4.0 * mil + 8.0), ctr + Vector2(wd, i * 4.0 * mil + 8.0), black, 1.5)
			ub.draw_line(ctr + Vector2(0, 16), ctr + Vector2(0, rad), black, 1.4)
			for sgn in [-1.0, 1.0]:
				ub.draw_line(ctr + Vector2(sgn * rad * 0.3, 0), ctr + Vector2(sgn * rad, 0), black, 4.0)
		else:
			ub.draw_line(ctr - Vector2(rad, 0), ctr + Vector2(rad, 0), black, 1.2)
			ub.draw_line(ctr - Vector2(0, rad), ctr + Vector2(0, rad), black, 1.2)
			for sgn in [-1.0, 1.0]:
				ub.draw_line(ctr + Vector2(sgn * rad * 0.42, 0), ctr + Vector2(sgn * rad, 0), black, 5.0)
				ub.draw_line(ctr + Vector2(0, rad * 0.42), ctr + Vector2(0, rad), black, 5.0)
				for i in range(1, 6):
					ub.draw_circle(ctr + Vector2(sgn * i * 5.0 * mil, 0), 2.0, black)
					ub.draw_circle(ctr + Vector2(0, i * 5.0 * mil), 2.0, black)
	elif not p.dead:
		if w.ads > 0.9 and optic == "rds":
			ub.draw_circle(ctr, 5.0, Color(1, 0.1, 0.05, 0.25))
			ub.draw_circle(ctr, 2.4, Color(1, 0.12, 0.08, 0.95))
		elif w.ads > 0.9 and optic == "holo":
			var hcol := Color(1, 0.14, 0.08, 0.9)
			ub.draw_arc(ctr, 17.0, 0.0, TAU, 40, hcol, 1.8)
			ub.draw_circle(ctr, 1.9, hcol)
			for v2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ub.draw_line(ctr + v2 * 17.0, ctr + v2 * 22.0, hcol, 1.8)
		elif w.ads < 0.6 and w.sprint_blend < 0.5:
			var a := 1.0 - w.ads / 0.6
			var gap := tan(deg_to_rad(w.spread_deg())) / tan(deg_to_rad(p.cam.fov * 0.5)) * sz.y * 0.5 + 4.0
			var col := Color(1, 1, 1, 0.85 * a)
			var sh := Color(0, 0, 0, 0.5 * a)
			for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ub.draw_line(ctr + v * gap, ctr + v * (gap + 10.0), sh, 4.0)
				ub.draw_line(ctr + v * gap, ctr + v * (gap + 10.0), col, 2.0)
			ub.draw_circle(ctr, 1.5, col)

	# --- маркер попадания
	if hit_t > 0.0:
		var hc := Color(1, 0.2, 0.15, 1) if hit_kill else (Color(1, 0.85, 0.3, 1) if hit_head else white)
		hc.a = clampf(hit_t / 0.15, 0.0, 1.0)
		var o := 7.0 + (0.3 - hit_t) * 14.0
		for v in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			ub.draw_line(ctr + v * o, ctr + v * (o + 9.0), hc, 2.5)

	# --- индикаторы урона
	for m in dmg_marks:
		var ang: float = -float(m[0])
		var col2 := Color(1, 0.12, 0.08, clampf(float(m[1]), 0.0, 1.0) * 0.85)
		ub.draw_arc(ctr, 150.0, ang - PI * 0.5 - 0.28, ang - PI * 0.5 + 0.28, 12, col2, 7.0)

	# --- компас
	var bearing := fposmod(-rad_to_deg(p.yaw), 360.0)
	var cw := 440.0
	var cy := 34.0
	var ppd := cw / 120.0
	ub.draw_rect(Rect2(ctr.x - cw * 0.5, cy - 20.0, cw, 34.0), Color(0, 0, 0, 0.28))
	var start := int(floor((bearing - 60.0) / 15.0)) * 15
	for deg in range(start, start + 135, 15):
		var x := ctr.x + (deg - bearing) * ppd
		if absf(x - ctr.x) > cw * 0.5 - 6.0:
			continue
		var dn := posmod(deg, 360)
		var label := ""
		match dn:
			0: label = "С"
			90: label = "В"
			180: label = "Ю"
			270: label = "З"
			_: label = str(dn) if dn % 45 == 0 else ""
		ub.draw_line(Vector2(x, cy + 6.0), Vector2(x, cy + 13.0), white, 1.5)
		if label != "":
			text(c, Vector2(x - 30.0, cy + 2.0), label, 16 if label.length() == 1 else 12, sand if label.length() == 1 else white, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	ub.tri(Rect2(ctr.x - 5.0, cy + 15.0, 10.0, 8.0), sand, false)
	text(c, Vector2(ctr.x - 40.0, cy + 40.0), "%03d°" % int(bearing), 14, white, HORIZONTAL_ALIGNMENT_CENTER, 80.0)

	# --- задачи и метки целей
	var mis: Mission = Game.mission
	if mis:
		_goal_list(c, p, mis)
		if not map.open:
			_goal_marks(c, p, mis)
		for o in mis.objectives:
			var done: bool = o.done
			var locked: bool = o.get("locked", false)
			if not done and not locked:
				var to: Vector3 = (o.pos as Vector3) - p.global_position
				var ob := rad_to_deg(atan2(to.x, -to.z))
				var diff := wrapf(ob - bearing, -180.0, 180.0)
				var mx := ctr.x + clampf(diff, -58.0, 58.0) * ppd
				var mc := Color(1.0, 0.8, 0.25)
				ub.tri(Rect2(mx - 6.0, cy - 17.0, 12.0, 11.0), mc, true)
				text(c, Vector2(mx - 40.0, cy + 58.0 + (14.0 if absf(diff) < 6.0 else 0.0)), "%d м" % int(to.length()), 12, mc, HORIZONTAL_ALIGNMENT_CENTER, 80.0)

	# --- ближайший ящик с боеприпасами на компасе (синяя метка)
	var best_a := Vector3.INF
	for ap in Game.level.ammo_points:
		if best_a == Vector3.INF or (ap as Vector3).distance_to(p.global_position) < best_a.distance_to(p.global_position):
			best_a = ap
	if best_a != Vector3.INF:
		var ta: Vector3 = best_a - p.global_position
		var da := wrapf(rad_to_deg(atan2(ta.x, -ta.z)) - bearing, -180.0, 180.0)
		var ax2 := ctr.x + clampf(da, -58.0, 58.0) * ppd
		var blue := Color(0.45, 0.75, 1.0)
		ub.draw_rect(Rect2(ax2 - 5.0, cy - 17.0, 10.0, 9.0), blue)
		if w.reserve[w.cur] <= int(d.mag):
			text(c, Vector2(ax2 - 50.0, cy + 72.0), "патроны %d м" % int(ta.length()), 12, blue, HORIZONTAL_ALIGNMENT_CENTER, 100.0)

	# --- здоровье, броня, боезапас (низ по центру)
	var by := sz.y - 34.0
	var bx := ctr.x - 250.0
	ub.draw_rect(Rect2(bx, by, 170.0, 10.0), Color(0, 0, 0, 0.45))
	var hc2 := Color(0.85, 0.2, 0.15) if p.hp < 35.0 else Color(0.9, 0.9, 0.86)
	ub.draw_rect(Rect2(bx, by, 170.0 * clampf(p.hp / 100.0, 0.0, 1.0), 10.0), hc2)
	ub.draw_rect(Rect2(bx, by + 13.0, 170.0, 5.0), Color(0, 0, 0, 0.45))
	ub.draw_rect(Rect2(bx, by + 13.0, 170.0 * clampf(p.armor / 60.0, 0.0, 1.0), 5.0), Color(0.45, 0.65, 0.9))
	if p.stamina < 99.0:
		ub.draw_rect(Rect2(bx, by - 7.0, 170.0 * p.stamina / 100.0, 3.0), Color(0.95, 0.85, 0.4, 0.8))
	text(c, Vector2(bx, by - 12.0), "%d" % int(ceil(p.hp)), 20, hc2)
	text(c, Vector2(bx + 56.0, by - 12.0), "АПТ %d" % w.medkits, 15, white)
	text(c, Vector2(bx + 118.0, by - 12.0), "ГР %d" % w.grenades, 15, white)
	var ax := ctr.x + 90.0
	var ac := Color(1, 0.35, 0.25) if w.ammo[w.cur] <= int(d.mag) / 5 else white
	text(c, Vector2(ax, by + 14.0), "%d" % w.ammo[w.cur], 34, ac)
	text(c, Vector2(ax + 62.0, by + 14.0), "/ %d" % w.reserve[w.cur], 18, Color(1, 1, 1, 0.7))
	text(c, Vector2(ax, by - 20.0), "%s · %s" % [d.name, d.cal], 13, sand)
	if bool(d.auto) and not Settings.touch_ui:
		text(c, Vector2(ax + 120.0, by + 14.0), "ОДИН." if w.semi[w.cur] else "АВТО", 13, white)
	if w.reload_t > 0.0:
		text(c, Vector2(ctr.x - 100.0, ctr.y + 70.0), "ПЕРЕЗАРЯДКА", 14, white, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
		ub.draw_rect(Rect2(ctr.x - 60.0, ctr.y + 78.0, 120.0 * (1.0 - w.reload_t / w.reload_total), 3.0), sand)
	elif w.heal_t > 0.0:
		text(c, Vector2(ctr.x - 100.0, ctr.y + 70.0), "ПЕРЕВЯЗКА", 14, white, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
		ub.draw_rect(Rect2(ctr.x - 60.0, ctr.y + 78.0, 120.0 * (1.0 - w.heal_t / 2.2), 3.0), sand)

	# --- подсказка взаимодействия и сообщения
	if prompt != "":
		var hint := prompt if Settings.touch_ui else "[F] " + prompt
		text(c, Vector2(ctr.x - 250.0, sz.y * 0.64), hint, 18, white, HORIZONTAL_ALIGNMENT_CENTER, 500.0)
		if prompt_progress > 0.0:
			ub.draw_rect(Rect2(ctr.x - 90.0, sz.y * 0.64 + 12.0, 180.0, 6.0), Color(0, 0, 0, 0.5))
			ub.draw_rect(Rect2(ctr.x - 90.0, sz.y * 0.64 + 12.0, 180.0 * prompt_progress, 6.0), sand)
	if message_t > 0.0:
		var mc2 := Color(1, 0.93, 0.7, clampf(message_t, 0.0, 1.0))
		text(c, Vector2(ctr.x - 400.0, 128.0), message, 20, mc2, HORIZONTAL_ALIGNMENT_CENTER, 800.0)
	if Settings.data.show_fps:
		text(c, Vector2(22, sz.y - 14.0), "%d FPS · %d%%" % [Engine.get_frames_per_second(), int(Settings.dyn_scale * 100.0)], 12, white)
