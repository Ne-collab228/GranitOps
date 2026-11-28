extends SceneTree
## Проверка звуков: godot --headless --audio-driver Dummy --path . -s tools/sfx_test.gd
## Все имена и варианты загружаются, API Sfx не падает.

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	var sfx: Node = root.get_node("Sfx")
	var n := 0
	var total_len := 0.0
	for k in sfx.variants:
		for s in sfx.variants[k]:
			n += 1
			total_len += (s as AudioStream).get_length()
	print("звуков: %d имён, %d файлов, %.0f с суммарно" % [sfx.variants.size(), n, total_len])
	var need := ["shot_ar", "shot_akm", "shot_smg", "shot_lmg", "shot_dmr", "shot_sg", "shot_sr", "shot_pistol", "shot_rifle", "shot_sniper",
		"shot_enemy", "shot_ar_far", "shot_pistol_supp", "mag_in", "mag_out", "bolt", "bolt_action", "pistol_slide", "dry", "casing",
		"hit_dirt", "hit_concrete", "hit_metal", "hit_wood", "hit_sheet", "hit_body", "ricochet", "whizz", "explosion", "explosion_far",
		"car_crash", "engine_idle", "engine_run", "engine_high", "step_dirt", "step_concrete", "step_metal", "step_wood", "step_gravel",
		"ui_click", "beep", "radio", "heartbeat", "fire", "amb_valley", "amb_airfield", "amb_pass", "amb_port", "ring", "pin", "cloth", "bounce",
		"hitmark", "killmark"]
	var bad := 0
	for k in need:
		if not sfx.has_sound(k):
			print("НЕТ ЗВУКА: ", k)
			bad += 1
	for k in ["heartbeat", "fire", "engine_idle", "amb_valley", "amb_port"]:
		var s: AudioStreamOggVorbis = sfx.streams[k]
		if not s.loop:
			print("НЕТ ПЕТЛИ: ", k)
			bad += 1
	for g in ["ar", "akm", "smg", "lmg", "dmr", "sg", "sr", "pistol"]:
		sfx.play("shot_" + g)
		sfx.play("shot_%s_supp" % g)
		sfx.gunshot("shot_" + g, Vector3(200, 0, 0), Vector3.ZERO)
	for surf in ["dirt", "concrete", "metal", "sheet", "wood", ""]:
		sfx.step(false, Vector3.ZERO, -8.0, true, surf)
		sfx.step(true, Vector3.ZERO, -8.0, false, surf)
	for m in 4:
		sfx.set_map(m)
		sfx.loop("wind", true, -9.0)
	sfx.engine(1, Vector3.ZERO, 0.5, 1.0)
	sfx.casing(0.1)
	print("ошибок: ", bad)
	quit(1 if bad > 0 else 0)
