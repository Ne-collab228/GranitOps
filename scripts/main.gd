extends Node
## Главная сцена: загрузка уровня, меню, запуск и завершение операции.

var world: Node3D
var level: Level
var menu: Menu
var hud: Hud
var menu_cam: Camera3D
var cam_t := 0.0
var paused := false
var ended := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# корневой вьюпорт переживает reload_current_scene: снять заморозку прошлой сцены
	get_viewport().disable_3d = false
	# прерванный тест памяти (рестарт сцены обрывает его корутину) мог оставить FXAA выключенным
	# или MSAA 2x — тот самый «течущий» режим; вернуть сглаживание из настроек
	Settings.aa_test_off = false
	Settings.apply()
	Engine.max_fps = int(Settings.data.fps_cap)
	if Mats.thermal_on:
		Mats.set_thermal(false)
	get_tree().paused = false
	Game.main = self
	Game.playing = false
	Game.enemies.clear()
	Game.vehicles.clear()
	Game.player = null
	Game.hud = null
	Game.mission = null
	Game.pickups.clear()
	var args := OS.get_cmdline_user_args()
	var map_id := int(Settings.data.map)
	for a in args:
		if a.begins_with("--map="):
			map_id = int(a.get_slice("=", 1))
			Settings.data.map = map_id
	menu = Menu.new()
	add_child(menu)
	menu.start_pressed.connect(start_mission)
	menu.resume_pressed.connect(toggle_pause)
	menu.restart_pressed.connect(restart.bind(true))
	menu.menu_pressed.connect(restart.bind(false))
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	level = Level.create(map_id)
	world.add_child(level)
	Game.level = level
	level.progress.connect(menu.set_loading)
	await get_tree().process_frame
	await level.build("--bake" in args)
	if "--bake" in args:
		get_tree().quit()
		return
	Game.fx = Fx.new()
	world.add_child(Game.fx)
	Game.ballistics = Ballistics.new()
	world.add_child(Game.ballistics)
	menu_cam = Camera3D.new()
	menu_cam.far = 2600.0
	menu_cam.fov = 60.0
	world.add_child(menu_cam)
	menu_cam.make_current()
	_orbit(0.0)
	Sfx.loop("wind", true, -15.0)
	if Game.arg_prefix("--walkshot"):
		_walkshot()
		return
	if Game.arg_prefix("--armshot"):
		_armshot()
		return
	if "--novsync" in args:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Settings.data.fps_cap = 0
		Engine.max_fps = 0
	if Game.autostart or "--play" in args or "--test" in args or "--touchtest" in args or Game.test_mode() or "--leaktest" in args:
		Game.autostart = false
		start_mission()
		if "--test" in args:
			_selftest()
		elif _soak_arg() > 0:
			_soak()
		elif "--touchtest" in args:
			_touchtest()
		elif Game.leaktest or "--leaktest" in args:
			Game.leaktest = false
			_leaktest()
		elif Game.arg_prefix("--gunshots"):
			_gunshots()
		elif "--bench" in args:
			_bench()
		elif "--vehtest" in args:
			_vehtest()
	else:
		await freeze_3d(true)
		menu.show_panel("main")
		if "--layouttest" in args:
			# редактор кнопок: открыть, перетащить «Огонь», уменьшить, проверить сохранение и вид в бою
			await _frames(40)
			Settings.data.btn_layout = {}
			menu.open_settings("main")
			menu.open_layout_editor()
			await _frames(20)
			await _shot("layout_0")
			var ed: TouchLayoutEditor = menu.layout_editor
			print("LAYOUT размеры: редактор=", ed.size, " панель=", (ed.get_parent() as Control).size, " корень=", menu.root.size, " видим=", ed.is_visible_in_tree())
			var from: Vector2 = ed._center_of("fire")
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = from
			ed._gui_input(ev)
			for k in 10:
				var mv := InputEventMouseMotion.new()
				mv.position = from + Vector2(-30.0, -18.0) * (k + 1)
				ed._gui_input(mv)
			ev = ev.duplicate()
			ev.pressed = false
			ed._gui_input(ev)
			ed.size_slider.value = 0.8
			await _frames(10)
			await _shot("layout_1")
			print("LAYOUT fire=", Settings.data.btn_layout.get("fire"), " было=", from, " стало=", ed._center_of("fire"))
			ed._finish()
			Game.autostart = true
			restart(true)
			return
		if "--menushot" in args:
			await _frames(90)
			await _shot("menu")
			menu.open_settings("main")
			await _frames(30)
			await _shot("settings")
			menu.show_panel("main")
			for gid in ["akm", "ar"]:
				menu.open_arsenal()
				menu.arsenal_ui.lo.slots[0] = gid
				menu.arsenal_ui.refresh_all()
				await _frames(40)
				await _shot("arsenal_" + gid)
			menu.arsenal_ui.sel_slot = "optic"
			menu.arsenal_ui.refresh_all()
			await _frames(30)
			await _shot("arsenal_optic")
			menu.arsenal_ui.slot_i = 2
			menu.arsenal_ui.refresh_all()
			await _frames(30)
			await _shot("arsenal_pistol")
			get_tree().quit()


func _orbit(delta: float) -> void:
	cam_t += delta
	var a := cam_t * 0.045 + 2.2
	var oc: Vector3 = level.orbit_center
	menu_cam.look_at_from_position(oc + Vector3(cos(a) * level.orbit_radius, level.orbit_height - oc.y, sin(a) * level.orbit_radius), oc, Vector3.UP)


var _dbg_t := 0.0


func _process(delta: float) -> void:
	if menu_cam and menu_cam.current and not Game.playing and not _frozen:
		_orbit(delta)
	_still_anim(delta)
	if "--perf" in OS.get_cmdline_user_args() and Game.playing:
		_dbg_t += delta
		if _dbg_t > 1.0:
			_dbg_t = 0.0
			var combat := 0
			var moving := 0
			for e in Game.enemies:
				if e.state == Enemy.St.COMBAT:
					combat += 1
				if not e.path.is_empty():
					moving += 1
			print("fps=%d proc=%.1fms phys=%.1fms nodes=%d bullets=%d combat=%d moving=%d draw=%d prim=%d hp=%d" % [
				Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Game.ballistics.bullets.size(), combat, moving,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Game.player.hp])


## Создать противника по описанию (как в Level.enemy_spawns) — и при старте, и при высадке из машины.
func spawn_enemy(sp: Dictionary) -> Enemy:
	var e := Enemy.new()
	e.setup(sp)
	world.add_child(e)
	Game.enemies.append(e)
	return e


func start_mission() -> void:
	Blackbox.event("старт миссии")
	Blackbox.note(Settings.summary())
	freeze_3d(false)
	Game.reset_stats()
	ended = false
	var p := Player.new()
	var spawn: Array = level.random_spawn() if not Game.test_mode() else [level.spawn_point, 0.0]
	p.position = spawn[0]
	p.yaw = spawn[1]
	world.add_child(p)
	Game.player = p
	for sp0 in level.enemy_spawns:
		var sp: Dictionary = (sp0 as Dictionary).duplicate()
		var route: PackedVector3Array = sp.route
		if not Game.test_mode():
			# каждый раз немного другая расстановка: часть постовых отсутствует, патрули начинают с разных точек
			if not bool(sp.hold) and int(sp.kind) != 2 and route.size() < 2 and randf() < 0.15:
				continue
			if route.size() > 1:
				sp.pos = route[randi() % route.size()] + Vector3(0, 0.05, 0)
		spawn_enemy(sp)
	level.spawn_vehicles(world)
	var m := Mission.new()
	world.add_child(m)
	m.setup(level)
	Game.mission = m
	hud = Hud.new()
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud)
	Game.hud = hud
	menu.show_panel("")
	Game.playing = true
	if not Settings.touch_ui:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_message("Операция началась. Цели отмечены на компасе", 5.0)
	Sfx.play("radio", -4.0)


func toggle_pause() -> void:
	if not Game.playing or ended:
		return
	paused = not paused
	get_tree().paused = paused
	_thermal_off()
	if paused:
		await freeze_3d(true)
		if not paused:
			return
	else:
		freeze_3d(false)
	menu.show_panel("pause" if paused else "")
	if not Settings.touch_ui:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if Game.playing and not paused and not ended and Settings.is_mobile:
			toggle_pause()


func _back() -> void:
	if menu.current == "settings":
		Settings.save()
		menu.show_panel(menu.back_to)
	elif menu.current == "layout":
		menu.layout_editor._finish()
	elif menu.current == "arsenal":
		Arsenal.store(menu.arsenal_ui.lo)
		menu._update_loadout_label()
		menu.show_panel("main")
	else:
		toggle_pause()


func restart(autostart: bool) -> void:
	Game.autostart = autostart
	Game.playing = false
	Sfx.stop_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func on_player_dead() -> void:
	Blackbox.event("смерть")
	ended = true
	await get_tree().create_timer(2.2).timeout
	finish(false)


func finish(success: bool) -> void:
	ended = true
	_thermal_off()
	Game.playing = false
	Sfx.loop("heartbeat", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if success:
		Sfx.play("radio")
	get_tree().paused = true
	await freeze_3d(true)
	menu.show_debrief(success, "Группа эвакуирована." if success else "Вы погибли.")


# ------------------------------------------------------------------ автотест (--test)
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://test_%s.png" % shot_name)


func _aim(p: Player, target: Vector3) -> void:
	var d := target - p.cam.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _selftest() -> void:
	var p: Player = Game.player
	p.hp = 100000.0
	await _frames(40)
	await _shot("0_spawn")
	p.t_ads = true
	await _frames(30)
	await _shot("1_ads_ar")
	p.t_ads = false
	var e: Enemy = Game.enemies[0]
	p.global_position = e.global_position + Vector3(1.5, 0.2, 24.0)
	await _frames(20)
	_aim(p, e.global_position + Vector3(0, 1.2, 0))
	await _frames(3)
	await _shot("2_enemy")
	p.t_fire = true
	for i in 70:
		if e.alive():
			_aim(p, e.global_position + Vector3(0, 1.15, 0))
		await get_tree().process_frame
		if i == 4:
			await _shot("3_firing")
	p.t_fire = false
	print("after AR burst: ", Game.stats, " enemy0 alive=", e.alive(), " hp=", p.hp)
	await _frames(30)
	await _shot("4_after")
	p.act("reload")
	await _frames(60)
	await _shot("5_reload")
	await _frames(120)
	p.act("weapon2")
	await _frames(50)
	await _shot("6_sniper")
	var e2: Enemy = Game.enemies[1]
	p.t_ads = true
	for i in 40:
		_aim(p, e2.global_position + Vector3(0, 1.2, 0))
		await get_tree().process_frame
	await _shot("7_scope")
	p.t_fire = true
	await _frames(2)
	p.t_fire = false
	await _frames(20)
	await _shot("8_bolt")
	await _frames(70)
	p.t_ads = false
	print("after sniper: ", Game.stats, " enemy1 alive=", e2.alive())
	p.act("weapon3")
	await _frames(50)
	await _shot("9_pistol")
	for i in 4:
		p.t_fire = true
		await _frames(2)
		p.t_fire = false
		await _frames(10)
	p.act("grenade")
	await _frames(230)
	await _shot("10_grenade")
	p.act("crouch")
	await _frames(20)
	p.act("jump")
	await _frames(20)
	p.act("heal")
	await _frames(150)
	p.act("weapon1")
	await _frames(40)
	# миссия: заряд на РЛС
	var rp: Vector3 = level.objectives.radar
	p.global_position = rp + Vector3(0.4, 0.2, 1.6)
	await _frames(10)
	_aim(p, rp)
	await _shot("11_radar")
	p.t_interact = true
	await _frames(200)
	p.t_interact = false
	p.global_position = rp + Vector3(6, 2.0, 34)
	await _frames(20)
	_aim(p, rp + Vector3(0, 2, 0))
	await get_tree().create_timer(8.6).timeout
	await _shot("12_explosion")
	await _frames(120)
	await _shot("13_burning")
	print("objectives: ", Game.mission.objectives.map(func(o): return [o.id, o.done]))
	print("enemy states: ", Game.enemies.map(func(en): return en.state))
	print("SELFTEST DONE ", Game.stats, " fps=", Engine.get_frames_per_second())
	get_tree().quit()


# ------------------------------------------------------------------ тест касаний (--touchtest)
var _k := Vector2.ONE


func _touch(i: int, canvas_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = i
	ev.position = canvas_pos * _k
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _swipe(i: int, canvas_pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = i
	ev.position = canvas_pos * _k
	ev.relative = rel * _k
	Input.parse_input_event(ev)


func _tap(canvas_pos: Vector2) -> void:
	_touch(5, canvas_pos, true)
	await _frames(3)
	_touch(5, canvas_pos, false)
	await _frames(3)


func _touchtest() -> void:
	var p: Player = Game.player
	p.hp = 100000.0
	await _frames(40)
	var vs := get_viewport().get_visible_rect().size
	_k = Vector2(DisplayServer.window_get_size()) / vs
	print("canvas=", vs, " window=", DisplayServer.window_get_size())
	var fire := Vector2(vs.x - 172.0, vs.y - 186.0)
	_touch(0, fire, true)
	await _frames(12)
	print("fire: held=", p.t_fire, " ammo=", p.weapons.ammo[0], " (was 30)")
	var yaw0 := p.yaw
	_swipe(0, fire + Vector2(-50, 0), Vector2(-50, 0))
	await _frames(3)
	print("aim while firing: yaw delta=", snappedf(p.yaw - yaw0, 0.001))
	_touch(0, fire, false)
	await _frames(3)
	print("fire released=", not p.t_fire)
	var js := Vector2(200.0, vs.y - 200.0)
	var pos0 := p.global_position
	_touch(1, js, true)
	_swipe(1, js + Vector2(0, -60), Vector2(0, -60))
	await _frames(40)
	print("stick walk: move=", p.t_move, " sprint=", p.t_sprint, " moved=", snappedf(p.global_position.distance_to(pos0), 0.01))
	_swipe(1, js + Vector2(0, -110), Vector2(0, -50))
	await _frames(40)
	print("stick sprint: move=", p.t_move, " sprint=", p.t_sprint, " sprinting=", p.sprinting, " speed=", snappedf(p.velocity.length(), 0.1))
	_touch(1, js, false)
	await _frames(5)
	print("stick released: move=", p.t_move)
	var lk := Vector2(vs.x * 0.62, vs.y * 0.35)
	yaw0 = p.yaw
	var pitch0 := p.pitch
	_touch(2, lk, true)
	_swipe(2, lk + Vector2(60, 25), Vector2(60, 25))
	await _frames(3)
	_touch(2, lk, false)
	print("look swipe: yaw delta=", snappedf(p.yaw - yaw0, 0.001), " pitch delta=", snappedf(p.pitch - pitch0, 0.001))
	await _tap(Vector2(vs.x - 64.0, vs.y - 266.0))
	print("ads toggled=", p.t_ads)
	await _frames(20)
	await _tap(Vector2(vs.x - 64.0, vs.y - 266.0))
	await _tap(Vector2(vs.x - 178.0, vs.y - 62.0))
	await _frames(10)
	print("crouching=", p.crouching)
	await _tap(Vector2(vs.x - 302.0, vs.y - 232.0))
	await _frames(40)
	print("weapon after switch=", p.weapons.cur)
	await _tap(Vector2(vs.x - 298.0, vs.y - 128.0))
	await _frames(5)
	print("reload started=", p.weapons.reload_t > 0.0, " (sniper full -> expected false)")
	await _tap(Vector2(vs.x - 216.0, vs.y - 322.0))
	await _frames(5)
	print("grenades left=", p.weapons.grenades)
	await _tap(Vector2(vs.x - 46.0, 46.0))
	await _frames(5)
	print("paused=", paused, " menu=", menu.current)
	await _shot("touch_pause")
	toggle_pause()
	await _frames(5)
	print("resumed=", not paused)
	menu.open_settings("main")
	await _frames(5)
	await _shot("touch_settings")
	menu.open_arsenal()
	var ui: ArsenalUI = menu.arsenal_ui
	for id in Arsenal.LONG + Arsenal.SIDE:
		ui.lo.slots[0 if id != "pistol" else 2] = id
		if ui.lo.slots[1] == id:
			ui.lo.slots[1] = "ar"
		ui.slot_i = 0 if id != "pistol" else 2
		ui.refresh_all()
		await _frames(9)
		await _shot("ars_" + id)
	print("TOUCHTEST DONE")
	get_tree().quit()


# ------------------------------------------------------------------ долгий прогон (--soak=<сек>)
func _soak_arg() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak="):
			return int(a.get_slice("=", 1))
	return 0


func _soak_log(tag: String) -> void:
	if "--drawdump" in OS.get_cmdline_user_args():
		draw_dump(tag)
	print("SOAK t=%d %s mem=%.1fMB peak=%.1fMB vmem=%.1fMB obj=%d res=%d nodes=%d orphans=%d bullets=%d fps=%d" % [
		Time.get_ticks_msec() / 1000, tag,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Game.ballistics.bullets.size(), Engine.get_frames_per_second()])


func _soak() -> void:
	var limit := _soak_arg() * 1000
	var p: Player = Game.player
	var log_t := 0
	var hop_t := 0
	var idx := 0
	var f := 0
	while Time.get_ticks_msec() < limit:
		await get_tree().process_frame
		if not is_instance_valid(p) or Game.player != p:
			return
		f += 1
		p.hp = 100000.0
		var now := Time.get_ticks_msec()
		if now - log_t > 5000:
			log_t = now
			_soak_log("run")
		var live: Array = Game.enemies.filter(func(x): return is_instance_valid(x) and x.alive())
		if live.is_empty():
			_soak_log("restart")
			restart(true)
			return
		var e: Enemy = live[idx % live.size()]
		if now - hop_t > 15000:
			hop_t = now
			idx += 1
			e = live[idx % live.size()]
			p.global_position = _test_hop(e.global_position + Vector3(randf_range(-6, 6), 0.0, randf_range(12, 20)))
		_aim(p, e.global_position + Vector3(0, 1.2, 0))
		p.t_fire = (f % 40) < 25
		if f % 600 == 0:
			p.weapons.refill()
		if f % 900 == 300:
			p.weapons.throw_grenade()
	_soak_log("end")
	get_tree().quit()


# ------------------------------------------------------------------ «заморозка» 3D
# В меню, на паузе и на экране итогов 3D-сцена не меняется, но телефон всё равно рисовал её
# каждый кадр (500+ вызовов отрисовки, 15–18 FPS в меню по отчёту) и грелся. Теперь снимаем
# один кадр без интерфейса, показываем его картинкой и отключаем 3D-рендер.
var _still_layer: CanvasLayer
var _still: TextureRect
var _frozen := false
var _still_t := 0.0


func freeze_3d(on: bool) -> void:
	if on == _frozen:
		return
	_frozen = on
	var vp := get_viewport()
	if not on:
		vp.disable_3d = false
		if _still_layer:
			_still_layer.visible = false
		Engine.max_fps = int(Settings.data.fps_cap)
		return
	if _still_layer == null:
		_still_layer = CanvasLayer.new()
		_still_layer.layer = -10
		add_child(_still_layer)
		_still = TextureRect.new()
		_still.set_anchors_preset(Control.PRESET_FULL_RECT)
		_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_still_layer.add_child(_still)
	var menu_vis: bool = menu.root.visible
	var hud_vis := hud != null and is_instance_valid(hud) and hud.visible
	menu.root.visible = false
	if hud_vis:
		hud.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if _frozen:
		_still.texture = ImageTexture.create_from_image(vp.get_texture().get_image())
		_still.pivot_offset = vp.get_visible_rect().size * 0.5
		_still.scale = Vector2.ONE
		_still_t = 0.0
		_still_layer.visible = true
		vp.disable_3d = true
		Engine.max_fps = 30
	menu.root.visible = menu_vis
	if hud_vis and is_instance_valid(hud):
		hud.visible = true


func _still_anim(delta: float) -> void:
	# едва заметный наезд камеры, чтобы фон меню не выглядел застывшим (2D — почти бесплатно)
	if _frozen and _still and not Game.playing:
		_still_t += delta
		var k := 1.0 + 0.06 * (0.5 - 0.5 * cos(_still_t * 0.08))
		_still.scale = Vector2(k, k)


# ------------------------------------------------------------------ отладка: что рисуется (--drawdump)
## Печатает, какие объекты попадают в кадр и сколько вызовов отрисовки/треугольников они дают
## (оценка: поверхности × экземпляры; тени не учитываются). Только для разработки.
func draw_dump(tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var planes := cam.get_frustum()
	var cp := cam.global_position
	var groups := {}
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is GeometryInstance3D) or not (n as GeometryInstance3D).is_visible_in_tree():
			continue
		var gi := n as GeometryInstance3D
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var aabb: AABB = gi.global_transform * gi.get_aabb()
		var dist := aabb.get_center().distance_to(cp)
		if gi.visibility_range_end > 0.0 and dist > gi.visibility_range_end + gi.visibility_range_end_margin:
			continue
		var inside := true
		for pl in planes:
			var c := aabb.get_center()
			var e := aabb.size * 0.5
			var r := absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z
			if pl.distance_to(c) > r:
				inside = false
				break
		if not inside:
			continue
		var draws := 0
		var tris := 0
		var mesh: Mesh = null
		var inst := 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
			inst = (gi as MultiMeshInstance3D).multimesh.visible_instance_count
			if inst < 0:
				inst = (gi as MultiMeshInstance3D).multimesh.instance_count
		if mesh:
			draws = mesh.get_surface_count()
			for si in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				var cnt: int = (idx as PackedInt32Array).size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				tris += cnt / 3 * inst
		var psc: Script = gi.get_parent().get_script()
		var key := String(gi.name).rstrip("0123456789_@").left(24) + " <" + (psc.resource_path.get_file() if psc else String(gi.get_parent().name).left(14)) + ">"
		if not groups.has(key):
			groups[key] = [0, 0, 0, gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF]
		groups[key][0] += 1
		groups[key][1] += draws
		groups[key][2] += tris
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][1] > groups[b][1])
	var td := 0
	var tt := 0
	for k in keys:
		td += groups[k][1]
		tt += groups[k][2]
	print("=== DRAWDUMP %s: оценка draw=%d tris=%dk (движок: draw=%d prim=%dk)" % [tag, td, tt / 1000,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	for k in keys.slice(0, 30):
		print("  %-46s узлов=%4d draw=%4d tris=%6dk тень=%s" % [k, groups[k][0], groups[k][1], groups[k][2] / 1000, groups[k][3]])


# ------------------------------------------------------------------ отладка: снимки оружия (--gunshots)
## Для каждого ствола: от бедра и в прицеле, без обвеса и с обвесом. Скриншоты gun_*.png в user://.
func _gunshots() -> void:
	var p: Player = Game.player
	var w: Weapons = p.weapons
	for e in Game.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	p.hp = 100000.0
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gunshots="):
			only = a.get_slice("=", 1)
	var sets := [["base", {}], ["kit", {"optic": "holo", "muzzle": "supp", "grip": "vert", "laser": "laser", "mag": "ext"}]]
	if "--scopes" in OS.get_cmdline_user_args():
		sets = [["therm", {"optic": "thermal"}], ["x10", {"optic": "x10"}], ["x6", {"optic": "x6"}]]
	for id in Arsenal.LONG + ["pistol"]:
		if only != "" and id != only:
			continue
		for st in sets:
			var att := Arsenal.default_att(id)
			for k in st[1]:
				if k in Arsenal.WEAPONS[id].slots:
					var ok := false
					for it in Arsenal.items_for(id, k):
						if it[0] == st[1][k]:
							ok = true
					if ok:
						att[k] = st[1][k]
			var m := GunModels.build(id, att)
			(w.models[w.cur].root as Node3D).queue_free()
			w.models[w.cur] = m
			w.defs[w.cur] = Arsenal.effective(id, att)
			w.add_child(m.root)
			(m.root as Node3D).position = m.hip
			p.t_ads = false
			await _frames(40)
			await _shot("gun_%s_%s_hip" % [id, st[0]])
			p.t_ads = true
			await _frames(70)
			await _shot("gun_%s_%s_ads" % [id, st[0]])
	get_tree().quit()


func _thermal_off() -> void:
	if Mats.thermal_on:
		Mats.set_thermal(false)
		if level:
			level.set_thermal(false)


# ------------------------------------------------------------------ отладка: руки крупно (--armshot)
func _armshot() -> void:
	Mats.vm_enabled = false
	menu.show_panel("")
	var root := Node3D.new()
	root.position = Vector3(0, 400, 0)
	world.add_child(root)
	for grip in [0, 1, 2]:
		for ch in root.get_children():
			ch.queue_free()
		var cm := BoxMesh.new()
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		if grip == 1:
			cm.size = Vector3(0.05, 0.05, 0.3)
			mi.position = Vector3(0, 0.0, 0)
		else:
			cm.size = Vector3(0.03, 0.11, 0.05)
			mi.rotation.x = -0.28 if grip == 0 else 0.0
		root.add_child(mi)
		if grip == 1:
			FPArms.build(root, Vector3(-0.2, -0.29, 0.27), Vector3(-0.034, -0.075, 0.055), Vector3(-0.004, -0.055, 0), 1, true)
		else:
			FPArms.build(root, Vector3(0.17 * (1 if grip == 0 else -1), -0.22, 0.27), Vector3(0.016, -0.1, 0.045), Vector3(0.003, -0.0, 0.012), grip, grip == 2)
		var cam := Camera3D.new()
		cam.fov = 40.0
		cam.near = 0.01
		root.add_child(cam)
		cam.current = true
		for v in [["side", Vector3(0.45, 0.02, 0.05)], ["front", Vector3(0.05, 0.05, -0.45)], ["fp", Vector3(0.04, 0.2, 0.42)]]:
			cam.look_at_from_position(root.position + v[1], root.position + Vector3(0, -0.04, 0.04), Vector3.UP)
			await _frames(4)
			await _shot("arms_g%d_%s" % [grip, v[0]])
	get_tree().quit()


# ------------------------------------------------------------------ отладка: цикл ходьбы бота (--walkshot)
func _walkshot() -> void:
	menu.show_panel("")
	var base := Vector3(0, 400, 0)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	floor_mi.mesh = pm
	floor_mi.position = base
	world.add_child(floor_mi)
	var e := Enemy.new()
	e.setup({"pos": base, "yaw": 0.0, "kind": 0, "route": PackedVector3Array(), "hold": true})
	world.add_child(e)
	await _frames(2)
	e.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 35.0
	world.add_child(cam)
	cam.current = true
	for sp in [1.6, 4.4]:
		e.velocity = Vector3(0, 0, -sp)
		await _frames(30)
		for k in 6:
			await _frames(3)
			cam.look_at_from_position(base + Vector3(3.2, 1.0, k * 0.05), base + Vector3(0, 0.9, 0), Vector3.UP)
			await _frames(2)
			await _shot("walk_%d_%d" % [int(sp * 10), k])
	get_tree().quit()


## Точка переноса бессмертного игрока в тестах: раньше бралась высота врага + 0.5 м, и на склоне
## (земля выше врага) игрок оказывался под рельефом. Теперь луч сверху вниз — на верх земли/крыши.
func _test_hop(at: Vector3) -> Vector3:
	var top := Vector3(at.x, maxf(at.y, level.ground(at.x, at.z)) + 40.0, at.z)
	var q := PhysicsRayQueryParameters3D.create(top, Vector3(at.x, -100.0, at.z), 1)
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit:
		return (hit.position as Vector3) + Vector3(0, 0.3, 0)
	return Vector3(at.x, level.ground(at.x, at.z) + 0.3, at.z)


# ------------------------------------------------------------------ тест машин (--vehtest)
## Игрок садится в ближайшую свободную машину, едет вперёд/поворачивает/тормозит; печатает скорость,
## снимает test_veh_*.png; затем следит за патрульными машинами ИИ.
func _vehtest() -> void:
	var p: Player = Game.player
	p.hp = 100000.0
	await _frames(30)
	print("VEH машин на карте: ", Game.vehicles.size(), " (ИИ: ", Game.vehicles.filter(func(v): return v.ai).size(), ")")
	var best: Vehicle = null
	for v in Game.vehicles:
		if v.is_free() and (best == null or v.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = v
	if best == null:
		print("VEH нет свободной машины")
		get_tree().quit()
		return
	print("VEH садимся: ", best.vid, " в ", best.global_position.distance_to(p.global_position), " м")
	p.global_position = best.exit_point()
	await _frames(5)
	p.enter_vehicle(best)
	await _frames(20)
	await _shot("veh_0_in")
	var phases := [["газ", Vector2(0, 1), 4.0], ["газ+вправо", Vector2(0.7, 1), 2.5], ["газ+влево", Vector2(-0.7, 1), 2.5], ["тормоз", Vector2(0, -1), 2.0], ["назад", Vector2(0, -1), 2.0]]
	var k := 1
	for ph in phases:
		p.t_move = ph[1]
		var t0 := Time.get_ticks_msec()
		var pos0 := best.global_position
		while Time.get_ticks_msec() - t0 < int(float(ph[2]) * 1000.0):
			p.hp = 100000.0
			await get_tree().process_frame
		print("VEH %-12s скорость %5.1f км/ч  смещение %5.1f м  наклон %.2f  руль %.2f" % [ph[0], best.speed * 3.6, best.global_position.distance_to(pos0), best.global_transform.basis.y.y, best.steering])
		await _shot("veh_%d" % k)
		k += 1
	p.t_move = Vector2.ZERO
	p.t_interact = true
	await _frames(3)
	p.t_interact = false
	await _frames(10)
	print("VEH вышли: в машине=", p.vehicle != null, " поз. игрока ", p.global_position)
	for i in 6:
		await _frames(60)
		var s := ""
		for v in Game.vehicles:
			if v.ai or v.ai_state == 1:
				s += "[%s %s v=%.0f kin=%s st=%d] " % [v.vid, Vector2(v.global_position.x, v.global_position.z).round(), v.speed * 3.6, v._kin, v.ai_state]
		print("VEH ИИ: ", s)
	get_tree().quit()


# ------------------------------------------------------------------ замер нагрузки (--bench)
## Повторяемый замер: камера по очереди в фиксированных точках, печатает вызовы отрисовки и треугольники
## (среднее за 20 кадров). Расстановка фиксирована (Game.test_mode). Для сравнения оптимизаций.
func _bench() -> void:
	var p: Player = Game.player
	var views := [["снаружи, вид на базу", Vector3(95, 0, 95), Vector3(0, 3, 0)],
		["двор, на север", Vector3(0, 0, -5), Vector3(0, 3, -60)],
		["у штаба, на восток", Vector3(-18, 0, -30), Vector3(40, 3, -30)],
		["у ангара, на запад", Vector3(50, 0, 30), Vector3(-30, 3, 20)],
		["с юга издалека", Vector3(0, 0, 150), Vector3(0, 3, 0)]]
	var shots := "--viewshot" in OS.get_cmdline_user_args()
	if shots:
		# дополнительные виды для оценки графики: здания вблизи, горизонт
		views.append_array([["штаб вблизи", Vector3(-14, 0, -24), Vector3(-30, 4, -42)],
			["казармы вблизи", Vector3(14, 0, -32), Vector3(26, 2.5, -48)],
			["ангар вблизи", Vector3(22, 0, 40), Vector3(38, 3, 22)],
			["горизонт с холма", Vector3(-118, 0, -70), Vector3(150, 10, 150)]])
	var lv: Array = level.bench_views()
	if not lv.is_empty():
		views = lv
	var td := 0
	var tp := 0
	if "--atlasdump" in OS.get_cmdline_user_args():
		await _frames(10)
		var aimg := (UiBatch.atlas as ImageTexture).get_image()
		aimg.clear_mipmaps()
		aimg.save_png("user://atlas.png")
		await _shot("hud_atlas")
		get_tree().quit()
		return
	if "--covershot" in OS.get_cmdline_user_args():
		# снимки укрытий в поле: стоим за укрытием, смотрим на базу
		var spots: Array = level._cover_spots
		print("COVER опорных точек: ", level.field_cover_count)
		var k := 0
		for i in range(0, spots.size(), 2):
			var cs: Vector3 = spots[i]
			var dirv := Vector2(-cs.x, -9.0 - cs.y).normalized()
			p.global_position = _test_hop(Vector3(cs.x - dirv.x * 9.0, 0, cs.y - dirv.y * 9.0))
			p.velocity = Vector3.ZERO
			_aim(p, Vector3(cs.x, level.ground(cs.x, cs.y) + 1.0, cs.y))
			await _frames(20)
			await _shot("cover_%d" % k)
			k += 1
			if k >= 12:
				break
		get_tree().quit()
		return
	if "--noshadow" in OS.get_cmdline_user_args():
		level.sun.shadow_enabled = false
	if "--nohud" in OS.get_cmdline_user_args():
		hud.visible = false
	for v in views:
		var at: Vector3 = v[1]
		p.global_position = _test_hop(at)
		p.velocity = Vector3.ZERO
		_aim(p, v[2] + Vector3(0, level.ground(v[2].x, v[2].z), 0))
		await _frames(25)
		var d := 0.0
		var pr := 0.0
		for i in 20:
			p.hp = 100000.0
			p.global_position = _test_hop(at)
			_aim(p, v[2] + Vector3(0, level.ground(v[2].x, v[2].z), 0))
			await get_tree().process_frame
			d += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			pr += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		print("BENCH %-24s draw=%4d prim=%4dk" % [v[0], int(d / 20.0), int(pr / 20000.0)])
		if shots:
			await _shot("view_%d" % views.find(v))
		if "--uidebug" in OS.get_cmdline_user_args():
			print("UI атлас=", UiBatch.atlas != null, " msdf=", UiBatch.is_msdf(hud.font), " шрифт=", hud.font)
		if "--drawdump" in OS.get_cmdline_user_args():
			draw_dump(v[0])
		td += int(d / 20.0)
		tp += int(pr / 20000.0)
	print("BENCH ИТОГО (среднее)          draw=%4d prim=%4dk" % [td / views.size(), tp / views.size()])
	get_tree().quit()


# ------------------------------------------------------------------ тест утечки памяти (кнопка в настройках)
## Бессмертный игрок воюет, а режимы сглаживания/свечения по очереди меняются на 15 с; в отчёт пишется
## прирост памяти (PSS) за каждую фазу — так видно, что именно «течёт» на телефоне.
func _leaktest() -> void:
	var p: Player = Game.player
	# 1.6 показал: течёт только 3D-рендер, а после сбоя буфера MSAA рост прекратился.
	# 1.7 проверяет догадку: новый режим (свой FXAA), без сглаживания, свечение, старый MSAA 2x, контроль.
	var glow_on := bool(Settings.data.glow)
	var phases := ["FXAA, без MSAA (новый режим)", "сглаживание выкл",
		"свечение " + ("выкл" if glow_on else "вкл"), "MSAA 2x (старый режим)", "FXAA (контроль после MSAA)"]
	Blackbox.event("ТЕСТ ПАМЯТИ 2: старт, свечение %s, масштаб %.2f" % ["вкл" if glow_on else "выкл", Settings.dyn_scale])
	hud.show_message("Тест памяти: 1,5 минуты, ничего не нажимайте", 6.0)
	var idx := 0
	for ph in phases.size():
		# вернуть обычный режим
		Settings.aa_test_off = false
		Settings.apply()
		level.apply_quality()
		match ph:
			1:
				Settings.aa_test_off = true
			2:
				level.env.glow_enabled = not glow_on
			3:
				Settings.aa_test_off = true
				get_viewport().msaa_3d = Viewport.MSAA_2X
		# сразу в бой: иначе первые до 10 с фазы игрок мог стоять далеко от врагов
		var live0: Array = Game.enemies.filter(func(x): return is_instance_valid(x) and x.alive())
		if not live0.is_empty():
			var e0: Enemy = live0[idx % live0.size()]
			p.global_position = _test_hop(e0.global_position + Vector3(randf_range(-6, 6), 0.0, randf_range(14, 22)))
		await _frames(30)
		var m0 := Blackbox.pss_mb()
		var t0 := Time.get_ticks_msec()
		var f0 := Engine.get_process_frames()
		while Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
			if not is_instance_valid(p) or Game.player != p:
				Settings.aa_test_off = false
				Settings.apply()
				return
			p.hp = 100000.0
			var live: Array = Game.enemies.filter(func(x): return is_instance_valid(x) and x.alive())
			if live.is_empty():
				Blackbox.note("ТЕСТ: враги кончились — фаза короче, цифры неточные")
				break
			var e2: Enemy = live[idx % live.size()]
			if Engine.get_process_frames() % 300 == 0:
				idx += 1
				p.global_position = _test_hop(e2.global_position + Vector3(randf_range(-6, 6), 0.0, randf_range(14, 22)))
			_aim(p, e2.global_position + Vector3(0, 1.2, 0))
			p.t_fire = (Engine.get_process_frames() % 40) < 20
			if Engine.get_process_frames() % 500 == 0:
				p.weapons.refill()
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		var m1 := Blackbox.pss_mb()
		var fps := (Engine.get_process_frames() - f0) / maxf(0.1, dt)
		Blackbox.note("ТЕСТ фаза %d «%s» (FXAA %s, MSAA %d): память %d -> %d МБ, %+.1f МБ/с, %.1f МБ/кадр*1000, fps %.0f" % [
			ph, phases[ph], "да" if Settings.fxaa_on() else "нет", get_viewport().msaa_3d, m0, m1, (m1 - m0) / maxf(0.1, dt), (m1 - m0) / maxf(1.0, fps * dt) * 1000.0, fps])
	Settings.aa_test_off = false
	Settings.apply()
	level.apply_quality()
	p.t_fire = false
	Blackbox.event("ТЕСТ ПАМЯТИ 2: конец")
	hud.show_message("Тест памяти завершён. Сохраните отчёт в настройках", 8.0)
