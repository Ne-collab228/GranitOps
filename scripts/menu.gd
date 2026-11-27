class_name Menu
extends CanvasLayer
## Меню: загрузка, главное, настройки, пауза, итоги операции.

signal start_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed

const SAND := Color(0.93, 0.86, 0.68)

var root: Control
var panels := {}
var back_to := "main"
var loading_label: Label
var settings_box: VBoxContainer
var debrief_title: Label
var debrief_text: Label
var current := ""

# --- оружейная
var arsenal_ui: ArsenalUI
var loadout_label: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _theme()
	add_child(root)
	_build_loading()
	_build_main()
	_build_settings_panel()
	_build_arsenal()
	_build_pause()
	_build_debrief()
	show_panel("loading")


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.11, 0.1, 0.82)
	normal.border_color = Color(0.93, 0.86, 0.68, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.2, 0.17, 0.9)
	hover.border_color = SAND
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.93, 0.86, 0.68, 0.9)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_pressed_color", cls, Color(0.08, 0.08, 0.07))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.06, 0.05, 0.86)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_constant("v_separation", "PopupMenu", 14)
	return t


func _panel(key: String, dim := 0.5) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	root.add_child(c)
	panels[key] = c
	return c


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable, min_w := 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 54)
	b.pressed.connect(func():
		Sfx.play("ui_click", -6.0)
		cb.call())
	return b


func show_panel(key: String) -> void:
	current = key
	for k in panels:
		(panels[k] as Control).visible = k == key
	root.visible = key != ""


func set_loading(text: String) -> void:
	loading_label.text = "Загрузка: %s…" % text


# ------------------------------------------------------------------ панели
func _build_loading() -> void:
	var c := _panel("loading", 1.0)
	(c.get_child(0) as ColorRect).color = Color(0.04, 0.05, 0.04)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var t := _label("ОПЕРАЦИЯ «ГРАНИТ»", 44, SAND)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	loading_label = _label("Загрузка…", 18, Color(1, 1, 1, 0.7))
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)


func _build_main() -> void:
	var c := _panel("main", 0.35)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	pc.offset_left = 50
	pc.offset_right = 470
	pc.offset_top = 40
	pc.offset_bottom = -40
	c.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	v.add_child(_label("ОПЕРАЦИЯ", 20, Color(1, 1, 1, 0.7)))
	v.add_child(_label("«ГРАНИТ»", 50, SAND))
	v.add_child(_label("Тактический шутер", 15, Color(1, 1, 1, 0.55)))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	v.add_child(_button("НАЧАТЬ ОПЕРАЦИЮ", func(): start_pressed.emit()))
	var diff := OptionButton.new()
	for d in ["Сложность: лёгкая", "Сложность: нормальная", "Сложность: тяжёлая"]:
		diff.add_item(d)
	diff.selected = int(Settings.data.difficulty)
	diff.custom_minimum_size = Vector2(300, 54)
	diff.item_selected.connect(func(i):
		Settings.data.difficulty = i
		Settings.save())
	v.add_child(diff)
	v.add_child(_button("ОРУЖЕЙНАЯ", open_arsenal))
	loadout_label = _label("", 13, Color(1, 1, 1, 0.6))
	loadout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(loadout_label)
	_update_loadout_label()
	v.add_child(_button("НАСТРОЙКИ", func(): open_settings("main")))
	if not Settings.is_mobile:
		v.add_child(_button("ВЫХОД", func(): get_tree().quit()))
	if Blackbox.crash_report != "":
		_build_crash_box(c)

	var brief := PanelContainer.new()
	brief.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	brief.offset_left = -560
	brief.offset_right = -50
	brief.offset_top = 40
	brief.offset_bottom = -40
	c.add_child(brief)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	brief.add_child(bv)
	bv.add_child(_label("БРИФИНГ", 22, SAND))
	var txt := _label(
		"Противник развернул в долине опорную базу. Вы высаживаетесь на южном гребне.\n\n" +
		"• Уничтожить РЛС на северо-западном холме\n" +
		"• Подорвать топливный склад на базе\n" +
		"• Забрать разведданные на втором этаже штаба\n" +
		"• Выйти к точке эвакуации на северо-востоке\n\n" +
		"Пули летят по баллистике: на дальних дистанциях берите упреждение и поправку по высоте. " +
		"Блик на вышке — снайпер. Выстрелы слышны далеко: тревога поднимает весь гарнизон.\n\n" +
		"Патроны: с убитых противников выпадают подсумки (подбираются на ходу), а армейские ящики " +
		"отмечены на компасе синим. Наведите прицел на противника — он будет отмечен красной меткой.", 16, Color(1, 1, 1, 0.85))
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bv.add_child(txt)
	var hint := "Управление: джойстик слева, обзор — свайп справа. Кнопку огня можно вести пальцем, прицеливаясь." if Settings.touch_ui \
		else "WASD — движение, ЛКМ — огонь, ПКМ — прицел, R — перезарядка, C — присесть, G — граната, H — аптечка, F — действие, 1/2/3 — оружие, B — режим огня, Q/E — наклон."
	var hl := _label(hint, 14, Color(1, 1, 1, 0.55))
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(hl)


func _build_pause() -> void:
	var c := _panel("pause", 0.55)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	var t := _label("ПАУЗА", 34, SAND)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_button("ПРОДОЛЖИТЬ", func(): resume_pressed.emit()))
	v.add_child(_button("НАСТРОЙКИ", func(): open_settings("pause")))
	v.add_child(_button("НАЧАТЬ ЗАНОВО", func(): restart_pressed.emit()))
	v.add_child(_button("В ГЛАВНОЕ МЕНЮ", func(): menu_pressed.emit()))


func _build_debrief() -> void:
	var c := _panel("debrief", 0.6)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.custom_minimum_size = Vector2(520, 0)
	c.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	debrief_title = _label("", 34, SAND)
	debrief_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(debrief_title)
	debrief_text = _label("", 18)
	v.add_child(debrief_text)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(_button("ЗАНОВО", func(): restart_pressed.emit(), 230.0))
	h.add_child(_button("В МЕНЮ", func(): menu_pressed.emit(), 230.0))


func show_debrief(success: bool, reason := "") -> void:
	var s: Dictionary = Game.stats
	debrief_title.text = "ЗАДАНИЕ ВЫПОЛНЕНО" if success else "ОПЕРАЦИЯ ПРОВАЛЕНА"
	debrief_title.add_theme_color_override("font_color", SAND if success else Color(0.95, 0.35, 0.28))
	var acc := 0.0
	if int(s.shots) > 0:
		acc = 100.0 * float(s.hits) / float(s.shots)
	var t := int(s.time)
	var lines := [
		reason,
		"Время: %d:%02d" % [t / 60, t % 60],
		"Уничтожено противников: %d (в голову: %d)" % [int(s.kills), int(s.headshots)],
		"Точность: %d%%  (%d выстрелов)" % [int(acc), int(s.shots)],
		"Самое дальнее поражение: %d м" % int(s.longest),
		"Получено урона: %d" % int(s.damage),
	]
	debrief_text.text = "\n".join(lines.filter(func(l): return l != ""))
	show_panel("debrief")


# ------------------------------------------------------------------ настройки
func open_settings(from: String) -> void:
	back_to = from
	_fill_settings()
	show_panel("settings")


func _build_settings_panel() -> void:
	var c := _panel("settings", 0.6)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pc.offset_left = 150
	pc.offset_right = -150
	pc.offset_top = 30
	pc.offset_bottom = -30
	c.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := _label("НАСТРОЙКИ", 28, SAND)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_button("НАЗАД", _settings_back, 160.0))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	settings_box = VBoxContainer.new()
	settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_box.add_theme_constant_override("separation", 8)
	sc.add_child(settings_box)


func _settings_back() -> void:
	Settings.save()
	show_panel(back_to)


func _row(text: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	var l := _label(text, 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	ctrl.custom_minimum_size = Vector2(300, 46)
	h.add_child(ctrl)
	settings_box.add_child(h)


func _opt(text: String, items: Array, selected: int, cb: Callable) -> void:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(selected, 0, items.size() - 1)
	o.item_selected.connect(cb)
	_row(text, o)


func _slider(text: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> void:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.value_changed.connect(cb)
	_row(text, s)


func _check(text: String, value: bool, cb: Callable) -> void:
	var o := OptionButton.new()
	o.add_item("Выкл")
	o.add_item("Вкл")
	o.selected = 1 if value else 0
	o.item_selected.connect(func(i): cb.call(i == 1))
	_row(text, o)


func _cfg(key: String, value) -> void:
	Settings.data[key] = value
	Settings.apply()


func _fill_settings() -> void:
	for ch in settings_box.get_children():
		ch.queue_free()
	var d: Dictionary = Settings.data
	settings_box.add_child(_label("ГРАФИКА  ·  %s" % Settings.gpu_name, 15, SAND))
	_opt("Качество графики", ["Низкое", "Среднее", "Высокое", "Ультра"], int(d.quality), func(i):
		Settings.set_preset(i)
		Settings.apply()
		_fill_settings.call_deferred())
	_slider("Разрешение рендера, %d%%" % int(float(d.scale) * 100.0), Settings.MIN_SCALE, 1.0, 0.05, float(d.scale), func(v):
		Settings.dyn_scale = v
		_cfg("scale", v))
	_check("Динамическое разрешение (держит FPS)", bool(d.dyn_res), func(v): _cfg("dyn_res", v))
	_opt("Тени", ["Выкл", "Низкие", "Средние", "Высокие", "Ультра"], int(d.shadows), func(i): _cfg("shadows", i))
	_opt("Сглаживание", ["Выкл", "FXAA"], clampi(int(d.aa), 0, 1), func(i): _cfg("aa", i))
	_check("Карты нормалей (рельеф поверхностей)", bool(d.normal_maps), func(v): _cfg("normal_maps", v))
	_opt("Трава и кусты", ["Минимум", "Средне", "Много"], int(d.veg), func(i): _cfg("veg", i))
	_check("Свечение (bloom)", bool(d.glow), func(v): _cfg("glow", v))
	var caps := [30, 45, 60, 90, 120, 0]
	_opt("Ограничение FPS", ["30", "45", "60", "90", "120", "Без ограничения"], maxi(0, caps.find(int(d.fps_cap))), func(i): _cfg("fps_cap", caps[i]))
	_check("Показывать FPS", bool(d.show_fps), func(v): _cfg("show_fps", v))
	_check("Метки обнаруженных противников", bool(d.marks), func(v): _cfg("marks", v))
	_check("Тепловизор: «чёрный горячий»", bool(d.get("thermal_bh", false)), func(v): _cfg("thermal_bh", v))
	var rep_status := _label("Отчёт о работе игры (FPS, память, ошибки) — для разработчика", 13, Color(1, 1, 1, 0.6))
	rep_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_box.add_child(rep_status)
	settings_box.add_child(_button("СОХРАНИТЬ ОТЧЁТ В ФАЙЛ", func(): rep_status.text = Blackbox.export_report()))
	settings_box.add_child(_button("ТЕСТ ПАМЯТИ (1,5 МИН)", func():
		Settings.save()
		Game.leaktest = true
		Game.main.restart(true)))
	if Settings.is_mobile:
		var modes := ["auto", "gl_compatibility", "mobile"]
		_opt("Рендер (нужен перезапуск)", ["Авто (OpenGL — быстрее)", "OpenGL ES", "Vulkan — красивее, тяжелее"], maxi(0, modes.find(String(d.renderer))),
			func(i): Settings.set_renderer(modes[i]))
	settings_box.add_child(_label("УПРАВЛЕНИЕ", 15, SAND))
	_slider("Чувствительность обзора", 0.3, 3.0, 0.05, float(d.sens), func(v): _cfg("sens", v))
	_slider("Чувствительность в прицеле", 0.3, 1.5, 0.05, float(d.ads_sens), func(v): _cfg("ads_sens", v))
	_check("Помощь в прицеливании", bool(d.aim_assist), func(v): _cfg("aim_assist", v))
	_check("Автоогонь при наведении на цель", bool(d.auto_fire), func(v): _cfg("auto_fire", v))
	_check("Прицел: переключение (а не удержание)", bool(d.toggle_ads), func(v): _cfg("toggle_ads", v))
	_check("Вторая кнопка огня слева", bool(d.left_fire), func(v): _cfg("left_fire", v))
	if Settings.touch_ui:
		settings_box.add_child(_button("РАСПОЛОЖЕНИЕ КНОПОК", open_layout_editor))
	_check("Гироскоп в прицеле", bool(d.gyro), func(v): _cfg("gyro", v))
	_check("Инверсия по вертикали", bool(d.invert_y), func(v): _cfg("invert_y", v))
	_check("Вибрация", bool(d.vibration), func(v): _cfg("vibration", v))
	_slider("Угол обзора", 60.0, 95.0, 1.0, float(d.fov), func(v): _cfg("fov", v))
	settings_box.add_child(_label("ЗВУК", 15, SAND))
	_slider("Громкость", 0.0, 1.0, 0.05, float(d.volume), func(v): _cfg("volume", v))


# ------------------------------------------------------------------ расположение кнопок
var layout_editor: TouchLayoutEditor


func open_layout_editor() -> void:
	if layout_editor == null:
		var c := _panel("layout", 0.3)
		layout_editor = TouchLayoutEditor.new()
		c.add_child(layout_editor)
		layout_editor.done.connect(func():
			Sfx.play("ui_click", -6.0)
			# вернуть кнопки боя (в паузе они не перерисовываются — показали бы старое расположение)
			if Game.hud and is_instance_valid(Game.hud) and Game.hud.touch:
				Game.hud.touch.visible = true
				Game.hud.touch.queue_redraw()
			show_panel("settings"))
	if Game.hud and is_instance_valid(Game.hud) and Game.hud.touch:
		Game.hud.touch.visible = false
	show_panel("layout")
	layout_editor.open()


# ------------------------------------------------------------------ оружейная
func _update_loadout_label() -> void:
	var lo := Arsenal.loadout()
	var names: Array = []
	for id in lo.slots:
		names.append(String(Arsenal.WEAPONS[id].name))
	loadout_label.text = "Снаряжение: " + ", ".join(names)


func open_arsenal() -> void:
	arsenal_ui.open()
	show_panel("arsenal")


func _build_arsenal() -> void:
	var c := _panel("arsenal", 0.0)
	arsenal_ui = ArsenalUI.new()
	c.add_child(arsenal_ui)
	arsenal_ui.done.connect(func():
		Arsenal.store(arsenal_ui.lo)
		_update_loadout_label()
		show_panel("main"))


## Отчёт «чёрного ящика» о прошлом аварийном завершении: весь текст с прокруткой (конец сразу виден)
## и кнопка сохранения в файл — пользователь присылает файл или вставляет текст из буфера обмена.
func _build_crash_box(c: Control) -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pc.offset_left = 30
	pc.offset_right = -30
	pc.offset_top = 20
	pc.offset_bottom = -20
	c.add_child(pc)
	# поверх брифинга (он добавляется в панель позже)
	pc.move_to_front.call_deferred()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	var head := "ИГРА БЫЛА СВЁРНУТА И ЗАКРЫТА (возможно, системой). Отчёт на всякий случай:" if Blackbox.prev_was_paused 		else "ПРОШЛЫЙ ЗАПУСК ЗАВЕРШИЛСЯ АВАРИЙНО. Сохраните отчёт и отправьте разработчику"
	var hl := _label(head, 16, SAND)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hl)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var txt := _label(Blackbox.crash_report, 12, Color(1, 1, 1, 0.9))
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(txt)
	# прокрутить к концу: самое важное — последние строки перед вылетом
	_scroll_end.call_deferred(sc)
	sc.visibility_changed.connect(func(): _scroll_end(sc))
	var status := _label("", 13, Color(0.7, 1, 0.7))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	row.add_child(_button("СОХРАНИТЬ В ФАЙЛ", func(): status.text = Blackbox.export_report()))
	row.add_child(_button("ЗАКРЫТЬ", func():
		Blackbox.crash_report = ""
		pc.queue_free()))


func _scroll_end(sc: ScrollContainer) -> void:
	for i in 3:
		await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
