extends Node
## Общий реестр игры. Автозагрузка "Game".

const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_DYN := 8
const L_FENCE := 16

var main: Node
var level: Level
var player: Player
var fx: Fx
var ballistics: Ballistics
var hud: Hud
var mission: Mission
var enemies: Array[Enemy] = []
var vehicles: Array[Vehicle] = []
var autostart := false
## Запуск теста памяти после перезагрузки сцены (кнопка в настройках).
var leaktest := false
## Отладка: не обновлять скелеты солдат (тест утечки).
var no_pose := false
var playing := false
var pickups: Array = []

var stats := {"shots": 0, "hits": 0, "kills": 0, "headshots": 0, "longest": 0.0, "damage": 0.0, "time": 0.0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()


func reset_stats() -> void:
	stats = {"shots": 0, "hits": 0, "kills": 0, "headshots": 0, "longest": 0.0, "damage": 0.0, "time": 0.0}
	pushers.clear()


## Шум в мире (выстрел, взрыв, шаги) — слышат противники в радиусе.
## Шум: проверять звук идут только двое ближайших, остальные занимают оборону на месте и смотрят в его сторону.
## Раньше на любой выстрел к игроку сбегался весь гарнизон.
func noise(pos: Vector3, radius: float) -> void:
	var heard: Array = []
	for e in enemies:
		if is_instance_valid(e) and e.alive() and e.global_position.distance_to(pos) <= radius:
			heard.append(e)
	heard.sort_custom(func(a, b): return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	var scouts := 0
	for e in heard:
		var go: bool = scouts < 2 and not e.hold and e.state != Enemy.St.INVESTIGATE
		if go:
			scouts += 1
		e.hear(pos, radius, go)


## Сколько противников сейчас идут в атаку на игрока (не больше двух одновременно).
var pushers := {}


func difficulty() -> int:
	return int(Settings.data.difficulty)


func _key(action: String, keys: Array) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _pad(action: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _axis(action: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "crouch_hold",
			"jump", "fire", "ads", "reload", "interact", "grenade", "heal", "weapon1", "weapon2",
			"weapon3", "next_weapon", "prev_weapon", "firemode", "lean_left", "lean_right", "pause"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.3)
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("crouch", [KEY_C])
	_key("crouch_hold", [KEY_CTRL])
	_key("jump", [KEY_SPACE])
	_key("reload", [KEY_R])
	_key("interact", [KEY_F])
	_key("grenade", [KEY_G])
	_key("heal", [KEY_H])
	_key("weapon1", [KEY_1])
	_key("weapon2", [KEY_2])
	_key("weapon3", [KEY_3])
	_key("firemode", [KEY_B])
	_key("lean_left", [KEY_Q])
	_key("lean_right", [KEY_E])
	_key("pause", [KEY_ESCAPE])
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("ads", MOUSE_BUTTON_RIGHT)
	_mouse("next_weapon", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("prev_weapon", MOUSE_BUTTON_WHEEL_UP)
	# геймпад
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis("ads", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad("jump", JOY_BUTTON_A)
	_pad("crouch", JOY_BUTTON_B)
	_pad("reload", JOY_BUTTON_X)
	_pad("next_weapon", JOY_BUTTON_Y)
	_pad("sprint", JOY_BUTTON_LEFT_STICK)
	_pad("interact", JOY_BUTTON_DPAD_UP)
	_pad("grenade", JOY_BUTTON_RIGHT_SHOULDER)
	_pad("heal", JOY_BUTTON_DPAD_DOWN)
	_pad("firemode", JOY_BUTTON_DPAD_LEFT)
	_pad("pause", JOY_BUTTON_START)


## Автотесты рассчитаны на фиксированную точку появления и полную расстановку противников.
func test_mode() -> bool:
	var a := OS.get_cmdline_user_args()
	return "--test" in a or "--touchtest" in a or arg_prefix("--gunshots") or "--bench" in a or "--vehtest" in a or "--roadcheck" in a


## Есть ли аргумент командной строки, начинающийся с prefix.
func arg_prefix(prefix: String) -> bool:
	for x in OS.get_cmdline_user_args():
		if x.begins_with(prefix):
			return true
	return false
