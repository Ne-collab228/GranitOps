class_name TouchLayoutEditor
extends Control
## Редактор расположения сенсорных кнопок (Настройки → «Расположение кнопок»).
## Кнопку тянут пальцем; у выбранной меняется размер; общий ползунок прозрачности.
## Сохраняется в Settings.data.btn_layout: id -> [x доля ширины, y доля высоты, масштаб].
## Касания приходят как события мыши (emulate_mouse_from_touch), поэтому работает и на ПК.

signal done

const NAMES := {
	"stick": "Джойстик", "fire": "Огонь", "fire2": "Огонь (слева)", "ads": "Прицел", "jump": "Прыжок",
	"crouch": "Присесть", "reload": "Перезарядка", "switch": "Смена оружия", "grenade": "Граната",
	"heal": "Аптечка", "mode": "Режим огня", "pause": "Пауза", "interact": "Действие", "thermal": "Тепловизор",
}
const TEXT_BTN := {"mode": "АВТ", "thermal": "БГ", "interact": ""}

var lay := {}
var sel := ""
var _drag := false
var _drag_off := Vector2.ZERO
var title: Label
var size_slider: HSlider
var alpha_slider: HSlider
var font: Font
var bar: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	bar = PanelContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -380
	bar.offset_right = 380
	bar.offset_top = 8
	add_child(bar)
	var v := VBoxContainer.new()
	bar.add_child(v)
	var h1 := HBoxContainer.new()
	v.add_child(h1)
	title = Label.new()
	title.custom_minimum_size = Vector2(300, 0)
	title.add_theme_font_size_override("font_size", 18)
	h1.add_child(title)
	var sl := Label.new()
	sl.text = "Размер"
	h1.add_child(sl)
	size_slider = HSlider.new()
	size_slider.min_value = 0.6
	size_slider.max_value = 1.6
	size_slider.step = 0.05
	size_slider.custom_minimum_size = Vector2(300, 40)
	size_slider.value_changed.connect(_on_size)
	h1.add_child(size_slider)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 8)
	v.add_child(h2)
	var al := Label.new()
	al.text = "Прозрачность"
	h2.add_child(al)
	alpha_slider = HSlider.new()
	alpha_slider.min_value = 0.3
	alpha_slider.max_value = 1.0
	alpha_slider.step = 0.05
	alpha_slider.custom_minimum_size = Vector2(160, 40)
	alpha_slider.value_changed.connect(func(x: float) -> void:
		Settings.data.btn_alpha = x
		queue_redraw())
	h2.add_child(alpha_slider)
	for bt in [["СБРОСИТЬ КНОПКУ", _reset_one], ["СБРОСИТЬ ВСЁ", _reset_all], ["ГОТОВО", _finish]]:
		var b := Button.new()
		b.text = bt[0]
		b.custom_minimum_size = Vector2(0, 46)
		var cb: Callable = bt[1]
		b.pressed.connect(func():
			Sfx.play("ui_click", -6.0)
			cb.call())
		h2.add_child(b)


func open() -> void:
	var src = Settings.data.get("btn_layout", {})
	lay = (src as Dictionary).duplicate(true) if src is Dictionary else {}
	Settings.data.btn_layout = lay
	alpha_slider.set_value_no_signal(float(Settings.data.get("btn_alpha", 1.0)))
	_select("fire")
	queue_redraw()


func _items() -> Array:
	# [id, центр, радиус] — все кнопки, включая те, что видны только иногда
	var out: Array = [["stick", TouchControls.stick_rest(size), TouchControls.stick_r()]]
	for b in TouchControls.BTN:
		out.append([String(b[0]), TouchControls.btn_pos_for(b, size), TouchControls.btn_r(b)])
	return out


func _select(id: String) -> void:
	sel = id
	title.text = "Кнопка: " + String(NAMES.get(id, id))
	size_slider.set_value_no_signal(_scale_of(id))


func _scale_of(id: String) -> float:
	var l := TouchControls.layout_of(id)
	return float(l[2]) if not l.is_empty() else 1.0


func _place(id: String, pos: Vector2, sc: float) -> void:
	# держим кнопку целиком на экране
	var base_r := TouchControls.STICK_R if id == "stick" else 40.0
	for b in TouchControls.BTN:
		if String(b[0]) == id:
			base_r = float(b[4])
	var r := base_r * sc
	pos.x = clampf(pos.x, r, size.x - r)
	pos.y = clampf(pos.y, r, size.y - r)
	# под верхнюю панель не пускаем — оттуда кнопку не достать
	var br := Rect2(bar.position, bar.size)
	if Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0).intersects(br):
		pos.y = maxf(pos.y, br.end.y + r)
	if size.x < 1.0 or size.y < 1.0:
		return
	lay[id] = [pos.x / size.x, pos.y / size.y, sc]
	Settings.data.btn_layout = lay
	queue_redraw()


func _center_of(id: String) -> Vector2:
	for it in _items():
		if it[0] == id:
			return it[1]
	return size * 0.5


func _on_size(v: float) -> void:
	if sel != "":
		_place(sel, _center_of(sel), v)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			# ближайшая кнопка под пальцем (с запасом); при наложении — меньшая сверху
			var best := ""
			var best_d := INF
			for it in _items():
				var d: float = (it[1] as Vector2).distance_to(mb.position)
				if d <= float(it[2]) * 1.15 and d / float(it[2]) < best_d:
					best = it[0]
					best_d = d / float(it[2])
			if best != "":
				_select(best)
				_drag = true
				_drag_off = _center_of(best) - mb.position
		else:
			_drag = false
		accept_event()
	elif event is InputEventMouseMotion and _drag and sel != "":
		_place(sel, (event as InputEventMouseMotion).position + _drag_off, _scale_of(sel))
		accept_event()


func _reset_one() -> void:
	lay.erase(sel)
	Settings.data.btn_layout = lay
	_select(sel)
	queue_redraw()


func _reset_all() -> void:
	lay.clear()
	Settings.data.btn_layout = lay
	_select(sel)
	queue_redraw()


func _finish() -> void:
	Settings.save()
	done.emit()


func _draw() -> void:
	var a := float(Settings.data.get("btn_alpha", 1.0))
	var line := Color(1, 1, 1, 0.7 * a)
	var col := Color(1, 1, 1, 0.92 * a)
	draw_string(font, Vector2(20, size.y - 16), "Перетащите кнопку пальцем. Размер выбранной — ползунком сверху.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
	for it in _items():
		var id: String = it[0]
		var c: Vector2 = it[1]
		var r: float = it[2]
		var on := id == sel
		draw_circle(c, r, Color(1, 1, 1, 0.18 * a) if on else Color(0, 0, 0, 0.25 * a))
		draw_arc(c, r, 0.0, TAU, 48, Color(1.0, 0.86, 0.5, 1.0) if on else line, 3.0 if on else 2.0, true)
		if id == "stick":
			draw_circle(c, 30.0 * r / TouchControls.STICK_R, Color(1, 1, 1, 0.3 * a))
		elif TEXT_BTN.has(id) and String(TEXT_BTN[id]) != "":
			draw_string(font, c + Vector2(-r, 5), TEXT_BTN[id], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, col)
		else:
			TouchControls.paint_icon(self, id, c, r / 40.0, col)
		if on:
			draw_string(font, c + Vector2(-80, -r - 10), String(NAMES.get(id, id)), HORIZONTAL_ALIGNMENT_CENTER, 160, 15, Color(1.0, 0.86, 0.5))
