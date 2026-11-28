extends Node
## Звук: пул 3D- и 2D-плееров. Автозагрузка "Sfx".
## Звуки — настоящие записи CC0 (assets/sfx/*.ogg, источники в LICENSES.md). У большинства по 2-4 варианта
## (name, name_2, name_3…): список и число вариантов лежит в scripts/sfx_names.gd (его пишет tools/build_sfx.py).

const SOUND_SPEED := 343.0
## Старые имена -> новые (чтобы вызовы из других скриптов продолжали работать). Варианты складываются.
const ALIASES := {
	"shot_rifle": ["shot_ar"], "shot_sniper": ["shot_sr"], "shot_enemy": ["shot_akm", "shot_ar"],
	"whizz0": ["whizz"], "whizz1": ["whizz"],
}
const LOOPS := ["heartbeat", "fire", "engine_idle", "engine_run", "engine_high", "amb_valley", "amb_airfield", "amb_pass", "amb_port"]
## Фоновый звук по картам (индексы Level.MAPS): долина, аэродром, перевал, порт.
const AMBIENCE := ["amb_valley", "amb_airfield", "amb_pass", "amb_port"]
## Дальше этой дистанции выстрел играется записью «вдали» (с эхом).
const FAR_SHOT_DIST := 75.0

var streams := {}      # имя -> первый вариант (нужен fx.gd, vehicle.gd для проверки наличия)
var variants := {}     # имя -> Array[AudioStream]
var _last := {}        # имя -> индекс последнего варианта (без повторов подряд)
var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _echo: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _ie := 0
var _loops := {}
var _amb := "amb_valley"
var _echo_t := 0.0
var _casing_t := 0.0
var _engines := {}     # id владельца -> {"p": [3 плеера], "t": время последнего вызова}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var names: Dictionary = SfxNames.VARIANTS
	for n in names:
		var list: Array = []
		for i in int(names[n]):
			var path := "res://assets/sfx/%s%s.ogg" % [n, "" if i == 0 else "_%d" % (i + 1)]
			var s: AudioStream = load(path) as AudioStream
			if s == null:
				push_warning("Sfx: не загрузился " + path)
				continue
			if n in LOOPS and s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			list.append(s)
		if not list.is_empty():
			variants[n] = list
			streams[n] = list[0]
	# звон в ушах остался сгенерированным
	var ring: AudioStream = load("res://assets/sfx/ring.wav") as AudioStream
	if ring:
		variants["ring"] = [ring]
		streams["ring"] = ring
	for a in ALIASES:
		if variants.has(a):
			continue
		for suffix in ["", "_far", "_supp"]:
			var merged: Array = []
			for t in ALIASES[a]:
				merged.append_array(variants.get(t + suffix, []))
			if not merged.is_empty():
				variants[a + suffix] = merged
				streams[a + suffix] = merged[0]
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 4200.0
		p.attenuation_filter_db = -22.0
		p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(p)
		_p3.append(p)
	for i in 12:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_p2.append(p2)
	for i in 3:
		var pe := AudioStreamPlayer.new()
		add_child(pe)
		_echo.append(pe)


## Выбор случайного варианта звука (подряд один и тот же не берём).
func pick(sound: String) -> AudioStream:
	var v: Array = variants.get(sound, [])
	if v.is_empty():
		return null
	if v.size() == 1:
		return v[0]
	var i := randi() % v.size()
	if i == int(_last.get(sound, -1)):
		i = (i + 1) % v.size()
	_last[sound] = i
	return v[i]


func has_sound(sound: String) -> bool:
	return variants.has(sound)


func play(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s := pick(sound)
	if s == null:
		return
	var p := _p2[_i2]
	_i2 = (_i2 + 1) % _p2.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.985, 1.015)
	p.play()
	# выстрел игрока: далёкое эхо от местности (запись «вдали», тише и ниже)
	if sound.begins_with("shot_") and not sound.ends_with("_supp") and not sound.ends_with("_far"):
		_echo_shot(sound, vol_db)


func _echo_shot(sound: String, vol_db: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _echo_t < 0.22 or not variants.has(sound + "_far"):
		return
	_echo_t = now
	var far := pick(sound + "_far")
	var pe := _echo[_ie]
	_ie = (_ie + 1) % _echo.size()
	get_tree().create_timer(randf_range(0.28, 0.42), false).timeout.connect(func() -> void:
		pe.stream = far
		pe.volume_db = vol_db - 17.0
		pe.pitch_scale = 0.92
		pe.play())


## Звук в точке мира. unit — «громкость источника» в метрах, delay — задержка (скорость звука).
func play_at(sound: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, unit := 10.0, max_dist := 120.0, delay := 0.0) -> void:
	if not variants.has(sound):
		return
	if delay > 0.03:
		get_tree().create_timer(delay, false).timeout.connect(play_at.bind(sound, pos, vol_db, pitch, unit, max_dist, 0.0))
		return
	var p := _p3[_i3]
	_i3 = (_i3 + 1) % _p3.size()
	p.stream = pick(sound)
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = unit
	p.max_distance = max_dist
	p.play()


## Выстрел, слышимый с учётом расстояния до слушателя: вблизи — сухая запись, вдали — с эхом.
func gunshot(sound: String, pos: Vector3, listener: Vector3, vol_db := 0.0) -> void:
	var d := pos.distance_to(listener)
	var snd := sound
	if d > FAR_SHOT_DIST and variants.has(sound + "_far"):
		snd = sound + "_far"
	play_at(snd, pos, vol_db, randf_range(0.97, 1.03), 42.0, 900.0, d / SOUND_SPEED)


## Шаг. surf — тип поверхности (dirt, concrete, metal, sheet, wood); без него — hard выбирает бетон или грунт.
func step(hard: bool, pos: Vector3, vol_db := -8.0, is_player := false, surf := "") -> void:
	var n: String
	match surf:
		"concrete":
			n = "step_concrete"
		"metal", "sheet":
			n = "step_metal"
		"wood":
			n = "step_wood"
		"dirt":
			n = "step_gravel" if randf() < 0.3 else "step_dirt"
		_:
			n = "step_concrete" if hard else ("step_gravel" if randf() < 0.3 else "step_dirt")
	if is_player:
		play(n, vol_db, randf_range(0.92, 1.08))
	else:
		play_at(n, pos, vol_db, randf_range(0.9, 1.1), 3.0, 30.0)


## Звон упавшей гильзы (через delay секунд). Не чаще, чем раз в 0.12 с.
func casing(delay := 0.3, vol_db := -14.0) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _casing_t < 0.12 or randf() < 0.25:
		return
	_casing_t = now
	get_tree().create_timer(delay + randf_range(0.0, 0.08), false).timeout.connect(play.bind("casing", vol_db, randf_range(0.9, 1.25)))


## Выбрать фон по карте (индекс Level.MAPS). Вызывать до loop("wind").
func set_map(map_id: int) -> void:
	var was: bool = _loops.has("wind") and (_loops["wind"] as AudioStreamPlayer).playing
	var vol: float = (_loops["wind"] as AudioStreamPlayer).volume_db if _loops.has("wind") else -8.0
	_amb = AMBIENCE[clampi(map_id, 0, AMBIENCE.size() - 1)]
	if _loops.has("wind"):
		(_loops["wind"] as AudioStreamPlayer).stop()
		(_loops["wind"] as AudioStreamPlayer).queue_free()
		_loops.erase("wind")
		if was:
			loop("wind", true, vol)


func _loop_name(sound: String) -> String:
	return _amb if sound == "wind" else sound


func loop(sound: String, on: bool, vol_db := 0.0) -> void:
	var key := sound
	var snd := _loop_name(sound)
	if on:
		if not _loops.has(key):
			var s: AudioStream = streams.get(snd)
			if s == null:
				return
			var p := AudioStreamPlayer.new()
			p.stream = s
			add_child(p)
			_loops[key] = p
		var lp: AudioStreamPlayer = _loops[key]
		lp.volume_db = vol_db
		if not lp.playing:
			lp.play()
	elif _loops.has(key):
		(_loops[key] as AudioStreamPlayer).stop()


## Двигатель машины: вызывать каждый кадр, пока он работает. owner_id — например get_instance_id().
## rpm 0..1 (от скорости), throttle 0..1 (газ). Три петли (холостой/ход/высокие) смешиваются по оборотам,
## высота растёт с оборотами. Если вызовы прекратились (машина уничтожена, игрок вышел) — звук сам стихнет.
func engine(owner_id: int, pos: Vector3, rpm: float, throttle := 0.0, vol_db := 0.0) -> void:
	if not variants.has("engine_idle"):
		return
	var e: Dictionary = _engines.get(owner_id, {})
	if e.is_empty():
		var arr: Array[AudioStreamPlayer3D] = []
		for n in ["engine_idle", "engine_run", "engine_high"]:
			var p := AudioStreamPlayer3D.new()
			p.stream = streams[n]
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p.attenuation_filter_cutoff_hz = 5000.0
			p.unit_size = 14.0
			p.max_distance = 220.0
			p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(p)
			p.play()
			arr.append(p)
		e = {"p": arr, "t": 0.0}
		_engines[owner_id] = e
	e["t"] = Time.get_ticks_msec() * 0.001
	var r := clampf(rpm, 0.0, 1.0)
	var th := clampf(throttle, 0.0, 1.0)
	var g_idle := clampf(1.0 - r * 2.2, 0.0, 1.0)
	var g_run := clampf(minf(r * 3.0, (1.0 - r) * 3.0 + 0.35), 0.0, 1.0)
	var g_high := clampf((r - 0.45) * 2.0, 0.0, 1.0)
	var gains := [g_idle, g_run, g_high]
	var pitches := [0.8 + r * 0.45, 0.72 + r * 0.85, 0.85 + r * 0.55]
	var ps: Array = e["p"]
	for i in 3:
		var p: AudioStreamPlayer3D = ps[i]
		p.global_position = pos
		p.pitch_scale = pitches[i] * (1.0 + th * 0.04)
		p.volume_db = vol_db + linear_to_db(maxf(float(gains[i]), 0.001)) + th * 3.0
		if not p.playing:
			p.play()


func _process(_delta: float) -> void:
	if _engines.is_empty():
		return
	var now := Time.get_ticks_msec() * 0.001
	for k in _engines.keys():
		var e: Dictionary = _engines[k]
		if now - float(e["t"]) > 0.3:
			for p in e["p"]:
				(p as AudioStreamPlayer3D).queue_free()
			_engines.erase(k)


func stop_all() -> void:
	for k in _loops:
		(_loops[k] as AudioStreamPlayer).stop()
	for p in _p3:
		p.stop()
	for k in _engines.keys():
		for p in _engines[k]["p"]:
			(p as AudioStreamPlayer3D).queue_free()
	_engines.clear()
