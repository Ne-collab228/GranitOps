extends Node
## Звук: пул 3D- и 2D-плееров. Автозагрузка "Sfx".

const NAMES := [
	"beep", "bolt", "bolt_action", "bounce", "cloth", "dry", "explosion", "fire", "heartbeat",
	"hit_body", "hit_concrete", "hit_dirt", "hit_metal", "hit_wood", "hitmark", "killmark",
	"mag_in", "mag_out", "pin", "pistol_slide", "radio", "ring", "shot_enemy", "shot_pistol",
	"shot_rifle", "shot_sniper", "step_gravel0", "step_gravel1", "step_gravel2", "step_gravel3",
	"step_hard0", "step_hard1", "step_hard2", "ui_click", "whizz0", "whizz1", "wind",
]
const SOUND_SPEED := 343.0

var streams := {}
var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _loops := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var s: AudioStream = load("res://assets/sfx/%s.wav" % n)
		if s:
			streams[n] = s
	for n in ["wind", "fire", "heartbeat"]:
		var w := streams.get(n) as AudioStreamWAV
		if w:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate) - 1
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 4200.0
		p.attenuation_filter_db = -22.0
		p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(p)
		_p3.append(p)
	for i in 8:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_p2.append(p2)


func play(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s: AudioStream = streams.get(sound)
	if s == null:
		return
	var p := _p2[_i2]
	_i2 = (_i2 + 1) % _p2.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


## Звук в точке мира. unit — «громкость источника» в метрах, delay — задержка (скорость звука).
func play_at(sound: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, unit := 10.0, max_dist := 120.0, delay := 0.0) -> void:
	var s: AudioStream = streams.get(sound)
	if s == null:
		return
	if delay > 0.03:
		get_tree().create_timer(delay, false).timeout.connect(play_at.bind(sound, pos, vol_db, pitch, unit, max_dist, 0.0))
		return
	var p := _p3[_i3]
	_i3 = (_i3 + 1) % _p3.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = unit
	p.max_distance = max_dist
	p.play()


## Выстрел, слышимый с учётом расстояния до слушателя.
func gunshot(sound: String, pos: Vector3, listener: Vector3, vol_db := 0.0) -> void:
	var d := pos.distance_to(listener)
	play_at(sound, pos, vol_db, randf_range(0.96, 1.04), 42.0, 900.0, d / SOUND_SPEED)


func step(hard: bool, pos: Vector3, vol_db := -8.0, is_player := false) -> void:
	var n := ("step_hard%d" % (randi() % 3)) if hard else ("step_gravel%d" % (randi() % 4))
	if is_player:
		play(n, vol_db, randf_range(0.9, 1.1))
	else:
		play_at(n, pos, vol_db, randf_range(0.9, 1.1), 3.0, 30.0)


func loop(sound: String, on: bool, vol_db := 0.0) -> void:
	if on:
		if not _loops.has(sound):
			var p := AudioStreamPlayer.new()
			p.stream = streams.get(sound)
			add_child(p)
			_loops[sound] = p
		var lp: AudioStreamPlayer = _loops[sound]
		lp.volume_db = vol_db
		if not lp.playing:
			lp.play()
	elif _loops.has(sound):
		(_loops[sound] as AudioStreamPlayer).stop()


func stop_all() -> void:
	for k in _loops:
		(_loops[k] as AudioStreamPlayer).stop()
	for p in _p3:
		p.stop()
