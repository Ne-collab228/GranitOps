class_name ArsenalUI
extends Control
## Оружейная: студия с крупной моделью ствола сбоку, вокруг — слоты обвеса с иконками и линиями к
## деталям; справа — варианты выбранного слота и характеристики; внизу — лента стволов.

signal done

const SAND := Color(0.93, 0.86, 0.68)
const ACCENT := Color(0.45, 0.86, 0.78)
const DRAWER_W := 360.0
## Положение карточек слотов в долях области ствола (слева от правой панели).
const SLOT_POS := {
	"muzzle": Vector2(0.05, 0.40), "barrel": Vector2(0.2, 0.17), "laser": Vector2(0.05, 0.64),
	"grip": Vector2(0.25, 0.73), "optic": Vector2(0.52, 0.13), "mag": Vector2(0.5, 0.76),
	"stock": Vector2(0.86, 0.3), "camo": Vector2(0.86, 0.6),
}
const BOX := Vector2(112, 96)


class StudioBg extends Control:
	func _draw() -> void:
		var s := size
		# вертикальный градиент тёмно-бирюзового «студийного» фона
		var top := Color(0.035, 0.07, 0.09)
		var bot := Color(0.06, 0.14, 0.17)
		var n := 24
		for i in n:
			var t := float(i) / n
			draw_rect(Rect2(0, s.y * t, s.x, s.y / n + 1), top.lerp(bot, t))
		# мягкое пятно света за стволом
		var c := Vector2((s.x - DRAWER_W) * 0.5, s.y * 0.45)
		for i in 14:
			var r := s.y * (0.62 - i * 0.04)
			draw_circle(c, r, Color(0.3, 0.62, 0.68, 0.018))
		# размытые светящиеся полосы на заднем плане
		for b in [[0.16, 0.18, 0.05, 0.07], [0.7, 0.12, 0.07, 0.05], [0.55, 0.62, 0.12, 0.02], [0.08, 0.7, 0.09, 0.02]]:
			for k in 5:
				var g := k * 6.0
				draw_rect(Rect2(s.x * b[0] - g, s.y * b[1] - g, s.x * b[2] + g * 2, s.y * b[3] + g * 2), Color(0.55, 0.85, 0.9, 0.025))
		# пол-подиум
		draw_rect(Rect2(0, s.y * 0.86, s.x, s.y * 0.14), Color(0, 0, 0, 0.25))
		draw_line(Vector2(0, s.y * 0.86), Vector2(s.x, s.y * 0.86), Color(0.5, 0.8, 0.85, 0.12), 1.0)


class SlotIcon extends Control:
	var kind := ""
	var col := Color(1, 1, 1, 0.85)

	func _draw() -> void:
		var s := size
		var c := s * 0.5
		var w := 2.0
		match kind:
			"optic":
				draw_rect(Rect2(c.x - 18, c.y - 6, 36, 10), col, false, w)
				draw_circle(Vector2(c.x - 20, c.y - 1), 7, col, false, w)
				draw_circle(Vector2(c.x + 20, c.y - 1), 6, col, false, w)
				draw_rect(Rect2(c.x - 8, c.y + 4, 4, 8), col)
				draw_rect(Rect2(c.x + 6, c.y + 4, 4, 8), col)
			"muzzle":
				draw_rect(Rect2(c.x - 20, c.y - 7, 40, 14), col, false, w)
				for i in 3:
					draw_line(Vector2(c.x - 10 + i * 10, c.y - 7), Vector2(c.x - 10 + i * 10, c.y + 7), col, w)
			"barrel":
				draw_rect(Rect2(c.x - 26, c.y - 3, 52, 6), col, false, w)
				draw_rect(Rect2(c.x + 18, c.y - 6, 8, 12), col)
			"grip":
				draw_rect(Rect2(c.x - 16, c.y - 12, 32, 6), col)
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6, c.y - 6), Vector2(c.x + 6, c.y - 6), Vector2(c.x + 5, c.y + 14), Vector2(c.x - 5, c.y + 14)]), col)
			"mag":
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - 9, c.y - 14), Vector2(c.x + 5, c.y - 14), Vector2(c.x + 14, c.y + 12), Vector2(c.x + 1, c.y + 15)]), col)
			"stock":
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - 22, c.y - 8), Vector2(c.x + 14, c.y - 10), Vector2(c.x + 22, c.y - 10), Vector2(c.x + 22, c.y + 12), Vector2(c.x + 12, c.y + 12), Vector2(c.x + 6, c.y - 2), Vector2(c.x - 22, c.y - 1)]), col)
			"laser":
				draw_rect(Rect2(c.x - 14, c.y - 6, 18, 12), col)
				draw_line(Vector2(c.x + 4, c.y), Vector2(c.x + 26, c.y), Color(1.0, 0.3, 0.25, 0.9), 2.0)
			"camo":
				for i in 3:
					for j in 2:
						var cc := col if (i + j) % 2 == 0 else Color(col, 0.35)
						draw_rect(Rect2(c.x - 18 + i * 12, c.y - 12 + j * 12, 11, 11), cc)


## Линии от карточек слотов к точкам на модели.
class Callouts extends Control:
	var links: Array = []  # [[точка_на_модели, прямоугольник_карточки, выбран]]

	func _draw() -> void:
		for l in links:
			var p: Vector2 = l[0]
			var r: Rect2 = l[1]
			var sel: bool = l[2]
			var c := r.get_center()
			var e := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
			if r.has_point(p):
				continue
			# выход из ближайшей стороны карточки
			if absf(p.x - c.x) / r.size.x > absf(p.y - c.y) / r.size.y:
				e = Vector2(r.end.x if p.x > c.x else r.position.x, c.y)
			else:
				e = Vector2(c.x, r.end.y if p.y > c.y else r.position.y)
			var col := ACCENT if sel else Color(1, 1, 1, 0.42)
			draw_line(e, p, col, 1.4 if sel else 1.0, true)
			draw_circle(p, 3.5, col)
			draw_circle(p, 7.0, Color(col, 0.25), false, 1.0)
			draw_rect(Rect2(e - Vector2(2.5, 2.5), Vector2(5, 5)), col)


class Bars extends Control:
	var rows: Array = []
	var font: Font

	func _draw() -> void:
		var y := 2.0
		for r in rows:
			draw_string(font, Vector2(0, y + 12.0), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, 172.0, 12, Color(1, 1, 1, 0.75))
			var x0 := 176.0
			draw_rect(Rect2(x0, y + 4.0, size.x - x0, 7.0), Color(1, 1, 1, 0.1))
			draw_rect(Rect2(x0, y + 4.0, (size.x - x0) * clampf(float(r[1]), 0.0, 1.0), 7.0), ACCENT)
			y += 20.0


var _svc: SubViewportContainer
var _fxaa_mat: ShaderMaterial
var lo := {}
var slot_i := 0
var sel_slot := ""
var spin := 0.0
var drag := false
var _drag_t := 0.0

var cam: Camera3D
var pivot: Node3D
var model: Node3D
var anchors := {}
var vp: SubViewport
var callouts: Callouts
var boxes := {}
var title: Label
var sub: Label
var tabs: Array = []
var strip: HBoxContainer
var drawer_title: Label
var drawer_list: VBoxContainer
var bars: Bars


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := StudioBg.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# 3D-витрина на весь экран
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	svc.gui_input.connect(_on_drag)
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	# MSAA на Mali течёт (см. Settings.apply) — витрину сглаживает FXAA на контейнере
	vp.msaa_3d = Viewport.MSAA_DISABLED
	_svc = svc
	_fxaa_mat = ShaderMaterial.new()
	_fxaa_mat.shader = Settings.fxaa_shader(false)
	_update_aa()
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.68, 0.74)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	for l in [[Vector3(-1.2, 1.4, 0.8), 2.0, Color(1.0, 0.96, 0.9)], [Vector3(-0.6, 0.3, -1.6), 1.1, Color(0.6, 0.85, 1.0)],
			[Vector3(1.0, 0.8, 0.6), 0.7, Color(0.7, 0.9, 0.95)], [Vector3(0.0, -1.0, 0.0), 0.35, Color(0.5, 0.8, 0.85)]]:
		var dl := DirectionalLight3D.new()
		dl.light_energy = l[1]
		dl.light_color = l[2]
		vp.add_child(dl)
		dl.look_at_from_position(l[0], Vector3.ZERO, Vector3.UP if absf((l[0] as Vector3).normalized().y) < 0.9 else Vector3.FORWARD)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.05
	cam.far = 20.0
	vp.add_child(cam)
	# сбоку слева: дуло слева, приклад справа
	cam.look_at_from_position(Vector3(-2.4, 0.05, 0.0), Vector3(0, 0.05, 0), Vector3.UP)
	cam.current = true
	pivot = Node3D.new()
	vp.add_child(pivot)

	callouts = Callouts.new()
	callouts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	callouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(callouts)

	# заголовок
	title = _label("", 34, SAND)
	title.position = Vector2(34, 18)
	add_child(title)
	sub = _label("", 15, Color(1, 1, 1, 0.6))
	sub.position = Vector2(36, 66)
	add_child(sub)
	# вкладки слотов и «Готово»
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-20, 16)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	for i in 3:
		var b := _button(Arsenal.SLOT_TITLES[i], func():
			slot_i = i
			sel_slot = ""
			refresh_all(), 150)
		b.toggle_mode = true
		top.add_child(b)
		tabs.append(b)
	top.add_child(_button("ГОТОВО", func(): done.emit(), 130))

	# карточки слотов
	for slot in SLOT_POS:
		var bx := Button.new()
		bx.custom_minimum_size = BOX
		bx.size = BOX
		bx.toggle_mode = true
		bx.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.09, 0.11, 0.78)
		sb.border_color = Color(1, 1, 1, 0.22)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		var sbs := sb.duplicate() as StyleBoxFlat
		sbs.border_color = ACCENT
		sbs.bg_color = Color(0.07, 0.16, 0.17, 0.9)
		sbs.set_border_width_all(2)
		bx.add_theme_stylebox_override("normal", sb)
		bx.add_theme_stylebox_override("hover", sbs)
		bx.add_theme_stylebox_override("pressed", sbs)
		bx.add_theme_stylebox_override("hover_pressed", sbs)
		var ic := SlotIcon.new()
		ic.kind = slot
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.position = Vector2(0, 6)
		ic.size = Vector2(BOX.x, 40)
		bx.add_child(ic)
		var t1 := _label(String(Arsenal.SLOTS[slot].title).to_upper(), 11, Color(1, 1, 1, 0.55))
		t1.position = Vector2(6, 48)
		t1.size = Vector2(BOX.x - 12, 14)
		t1.clip_text = true
		t1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bx.add_child(t1)
		var t2 := _label("", 12, SAND)
		t2.position = Vector2(6, 64)
		t2.size = Vector2(BOX.x - 12, 28)
		t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t2.clip_text = true
		t2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bx.add_child(t2)
		bx.pressed.connect(func():
			Sfx.play("ui_click", -6.0)
			sel_slot = "" if sel_slot == slot else slot
			_fill_drawer()
			_sync_boxes())
		add_child(bx)
		boxes[slot] = [bx, t2]

	# правая панель
	var dr := PanelContainer.new()
	dr.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	dr.offset_left = -DRAWER_W - 16
	dr.offset_right = -16
	dr.offset_top = 84
	dr.offset_bottom = -112
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.03, 0.07, 0.08, 0.82)
	dsb.border_color = Color(1, 1, 1, 0.12)
	dsb.set_border_width_all(1)
	dsb.set_corner_radius_all(4)
	dsb.set_content_margin_all(14)
	dr.add_theme_stylebox_override("panel", dsb)
	add_child(dr)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dr.add_child(dv)
	drawer_title = _label("", 17, SAND)
	dv.add_child(drawer_title)
	var dsc := ScrollContainer.new()
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(dsc)
	drawer_list = VBoxContainer.new()
	drawer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_list.add_theme_constant_override("separation", 6)
	dsc.add_child(drawer_list)
	dv.add_child(_label("ХАРАКТЕРИСТИКИ", 13, Color(1, 1, 1, 0.5)))
	bars = Bars.new()
	bars.font = ThemeDB.fallback_font
	bars.custom_minimum_size = Vector2(0, 150)
	dv.add_child(bars)

	# лента стволов
	var ssc := ScrollContainer.new()
	ssc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ssc.offset_left = 16
	ssc.offset_right = -16
	ssc.offset_top = -100
	ssc.offset_bottom = -12
	ssc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(ssc)
	strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	ssc.add_child(strip)


## Оружейная строится один раз — настройку сглаживания подхватываем при каждом открытии.
func _update_aa() -> void:
	_svc.material = _fxaa_mat if int(Settings.data.aa) > 0 else null


func open() -> void:
	_update_aa()
	lo = Arsenal.loadout()
	sel_slot = ""
	spin = 0.0
	refresh_all()


func refresh_all() -> void:
	for i in tabs.size():
		(tabs[i] as Button).set_pressed_no_signal(i == slot_i)
	for ch in strip.get_children():
		ch.queue_free()
	var cur: String = lo.slots[slot_i]
	for id in (Arsenal.SIDE if slot_i == 2 else Arsenal.LONG):
		var w: Dictionary = Arsenal.WEAPONS[id]
		var b := _button("%s\n%s" % [w.name, w.cls], func():
			var other := 1 - slot_i
			if slot_i < 2 and lo.slots[other] == id:
				lo.slots[other] = lo.slots[slot_i]
			lo.slots[slot_i] = id
			sel_slot = ""
			refresh_all(), 190)
		b.custom_minimum_size = Vector2(190, 78)
		b.add_theme_font_size_override("font_size", 15)
		b.toggle_mode = true
		b.set_pressed_no_signal(id == cur)
		strip.add_child(b)
	if sel_slot != "" and not (sel_slot in Arsenal.WEAPONS[cur].slots):
		sel_slot = ""
	_rebuild_model()
	_fill_drawer()
	_sync_boxes()


func _cur() -> String:
	return lo.slots[slot_i]


func _sync_boxes() -> void:
	var id := _cur()
	var att: Dictionary = lo.att[id]
	var slots: Array = Arsenal.WEAPONS[id].slots
	for slot in boxes:
		var bx: Button = boxes[slot][0]
		bx.visible = slot in slots
		bx.set_pressed_no_signal(slot == sel_slot)
		var cur_item := String(att.get(slot, ""))
		var nm := ""
		for it in Arsenal.items_for(id, slot) if slot in slots else []:
			if it[0] == cur_item:
				nm = it[1]
		(boxes[slot][1] as Label).text = nm


func _fill_drawer() -> void:
	for ch in drawer_list.get_children():
		ch.queue_free()
	var id := _cur()
	var att: Dictionary = lo.att[id]
	var d := Arsenal.effective(id, att)
	title.text = String(d.name).to_upper()
	sub.text = "%s  ·  %s  ·  магазин %d  ·  перезарядка %.1f с" % [d.cls, d.cal, int(d.mag), float(d.reload)]
	bars.rows = Arsenal.bars(d)
	bars.queue_redraw()
	if sel_slot == "":
		drawer_title.text = "ОБВЕС"
		var hint := _label("Нажмите на слот рядом с оружием, чтобы выбрать деталь. Модель можно вращать пальцем.", 14, Color(1, 1, 1, 0.6))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(DRAWER_W - 40, 0)
		drawer_list.add_child(hint)
		return
	drawer_title.text = String(Arsenal.SLOTS[sel_slot].title).to_upper()
	for it in Arsenal.items_for(id, sel_slot):
		var key: String = it[0]
		var txt: String = it[1]
		var h := String(Arsenal.HINTS.get(key, ""))
		var b := _button(txt + ("\n" + h if h != "" else ""), func():
			att[sel_slot] = key
			Sfx.play("ui_click", -6.0)
			_rebuild_model()
			_fill_drawer()
			_sync_boxes(), DRAWER_W - 40)
		b.custom_minimum_size = Vector2(DRAWER_W - 40, 58 if h != "" else 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 14)
		b.toggle_mode = true
		b.set_pressed_no_signal(att.get(sel_slot, "") == key)
		drawer_list.add_child(b)


func _rebuild_model() -> void:
	if model:
		model.queue_free()
		model = null
	var id := _cur()
	Mats.vm_enabled = false
	var m := GunModels.build(id, lo.att[id], false)
	Mats.vm_enabled = true
	model = m.root
	var bb := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b := mi.transform * mi.get_aabb()
		var p := mi.get_parent()
		var shown := mi.visible
		while p and p != model:
			b = (p as Node3D).transform * b
			shown = shown and (p as Node3D).visible
			p = p.get_parent()
		if not shown:
			continue
		bb = b if first else bb.merge(b)
		first = false
	# масштаб: длина ствола ~ 60% ширины области витрины (у пистолета меньше)
	var vis_h := 2.0 * 2.4 * tan(deg_to_rad(cam.fov * 0.5))
	var sz := get_viewport_rect().size
	var vis_w := vis_h * sz.x / maxf(1.0, sz.y)
	var area_w := vis_w * (sz.x - DRAWER_W - 32) / sz.x
	var want := area_w * (0.62 if id != "pistol" else 0.42)
	var k := want / maxf(0.2, bb.size.z)
	model.position = -bb.get_center()
	pivot.scale = Vector3.ONE * k
	# центр области ствола (левее центра экрана из-за правой панели)
	var cx := ((sz.x - DRAWER_W - 32) * 0.5) / sz.x
	pivot.position = Vector3(0, 0.02, (cx - 0.5) * vis_w)
	pivot.add_child(model)
	anchors = m.get("anchors", {})
	if anchors.is_empty():
		# модели без размеченных точек: по габаритам
		var c := bb.get_center()
		var e := bb.size * 0.5
		anchors = {"muzzle": Vector3(0, c.y + e.y * 0.3, bb.position.z), "barrel": Vector3(0, c.y + e.y * 0.3, c.z - e.z * 0.6),
			"optic": Vector3(0, bb.end.y, c.z), "grip": Vector3(0, c.y, c.z - e.z * 0.4), "mag": Vector3(0, bb.position.y + e.y * 0.4, c.z),
			"stock": Vector3(0, c.y, bb.end.z - e.z * 0.15), "laser": Vector3(0, c.y, c.z - e.z * 0.5), "camo": c}


func _on_drag(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		drag = ev.pressed
	elif ev is InputEventMouseMotion and drag:
		spin += ev.relative.x * 0.01
		_drag_t = 2.5
	elif ev is InputEventScreenDrag:
		spin += ev.relative.x * 0.01
		_drag_t = 2.5


func _process(delta: float) -> void:
	if not is_visible_in_tree() or pivot == null:
		return
	_drag_t -= delta
	if _drag_t <= 0.0 and not drag:
		# сам возвращается в профиль и чуть «дышит»
		spin = lerpf(spin, sin(Time.get_ticks_msec() * 0.0004) * 0.12, minf(1.0, delta * 2.0))
	pivot.rotation.y = spin
	_update_links()


func _update_links() -> void:
	var sz := get_viewport_rect().size
	var area := Vector2(sz.x - DRAWER_W - 32, sz.y - 120)
	var links: Array = []
	for slot in boxes:
		var bx: Button = boxes[slot][0]
		if not bx.visible:
			continue
		var f: Vector2 = SLOT_POS[slot]
		bx.position = Vector2(area.x * f.x, 90 + (area.y - 90) * f.y) - Vector2(0, BOX.y * 0.5)
		if model and anchors.has(slot):
			var wp: Vector3 = model.global_transform * (anchors[slot] as Vector3)
			if not cam.is_position_behind(wp):
				var sp := cam.unproject_position(wp) * (sz / Vector2(vp.size))
				links.append([sp, Rect2(bx.position, BOX), slot == sel_slot])
	callouts.links = links
	callouts.queue_redraw()


func _label(text: String, size_px: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable, min_w := 200.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 50)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Sfx.play("ui_click", -6.0)
		cb.call())
	return b
