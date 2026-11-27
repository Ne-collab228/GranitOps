extends Node
## «Чёрный ящик»: раз в 3 с пишет память/FPS/температуру/состояние и ошибки движка в user://blackbox.txt.
## Если прошлый запуск закончился не штатно (нет строки EXIT), текст доступен в `crash_report`
## и показывается в главном меню; кнопкой его можно сохранить в «Загрузки» телефона (`export_report`).

const PATH := "user://blackbox.txt"
const PREV := "user://blackbox_prev.txt"
const KEEP := 400

var _measure_on := false
var crash_report := ""
## Прошлый запуск завершился не штатно (не сбрасывается кнопкой «Закрыть», в отличие от crash_report).
var prev_crashed := false
var _dirty := false
var _flush_t := 0.0
var _log_lines := 0
## Последнее событие прошлого запуска было «свёрнуто» — скорее всего, игру закрыла система или
## пользователь из списка приложений, а не вылет.
var prev_was_paused := false
var _lines: PackedStringArray = []
var _t := 0.0
var _start_ms := 0
var _errors := 0
var _paused := false
## Журнал текущего запуска: user://logs/<дата_время>.txt, дописывается и сбрасывается на диск сразу.
const LOG_DIR := "user://journals"
const LOG_EVERY := 5  # каждый 5-й замер (по 2 с) = раз в 10 с
var session_file := ""
var _slog: FileAccess
var _tick := 0
var _skip_log := false
var _uploader: LogUploader
var _upload_started := false


class BoxLogger extends Logger:
	var box: Node

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := "WARN" if error_type == ERROR_TYPE_WARNING else "ERR"
		var msg := rationale if rationale != "" else code
		box.call_deferred("log_note", "%s %s (%s:%d %s)" % [kind, msg.left(160), file.get_file(), line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_ms = Time.get_ticks_msec()
	if FileAccess.file_exists(PATH):
		var old := FileAccess.get_file_as_string(PATH).strip_edges()
		if old != "":
			var f := FileAccess.open(PREV, FileAccess.WRITE)
			if f:
				f.store_string(old)
				f.close()
		if old != "" and not old.ends_with("EXIT"):
			crash_report = old
			prev_crashed = true
			var last := old.get_slice("\n", old.count("\n"))
			prev_was_paused = last.contains("СВЁРНУТО")
	var lg := BoxLogger.new()
	lg.box = self
	OS.add_logger(lg)
	_open_session_log()
	note("START %s %s %s, экран %s, ОЗУ всего %s, видео %s, рендер %s, версия %s" % [
		OS.get_model_name(), OS.get_name(), OS.get_version(), DisplayServer.window_get_size(), _mb_kb(_meminfo("MemTotal")),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		ProjectSettings.get_setting("application/config/version", "?")])
	_log_raw("УСТРОЙСТВО " + _device_name() + ", экран " + str(DisplayServer.screen_get_size()) + ", GPU " + RenderingServer.get_video_adapter_name())
	_log_raw(Settings.summary())
	_log_raw("карта=%d" % int(Settings.data.map))
	_uploader = LogUploader.new()
	_uploader.setup(session_file.get_file(), _device_slug())
	add_child(_uploader)


func _device_name() -> String:
	var m := OS.get_model_name()
	return "pc" if m == "" or m == "GenericDevice" else m


## Имя устройства для пути в репозитории: только буквы, цифры, «-», «_».
func _device_slug() -> String:
	var out := ""
	for c in _device_name():
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-" or c == "_":
			out += c
	return out if out != "" else "pc"


func _open_session_log() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var fname := stamp + ".txt"
	var n := 1
	while FileAccess.file_exists(LOG_DIR.path_join(fname)):
		n += 1
		fname = "%s_%d.txt" % [stamp, n]
	session_file = LOG_DIR.path_join(fname)
	_slog = FileAccess.open(session_file, FileAccess.WRITE)


## Строка в журнал запуска (с реальным временем) и немедленный сброс на диск.
func _log_raw(text: String) -> void:
	if _slog == null:
		return
	_slog.store_line("%s %s" % [Time.get_time_string_from_system(), text])
	_slog.flush()


## Значение из /proc/meminfo или /proc/self/status в килобайтах (-1, если недоступно).
static func _proc_kb(path: String, key: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := 0
	while not f.eof_reached() and n < 80:
		var ln := f.get_line()
		n += 1
		if ln.begins_with(key + ":"):
			return int(ln.get_slice(":", 1).strip_edges().get_slice(" ", 0))
	return -1


static func _meminfo(key: String) -> int:
	var v := _proc_kb("/proc/meminfo", key)
	if v < 0:
		var mi := OS.get_memory_info()
		var k := {"MemTotal": "physical", "MemAvailable": "available"}.get(key, "") as String
		if k != "" and int(mi.get(k, -1)) > 0:
			v = int(mi[k]) / 1024
	return v


static func _mb_kb(kb: int) -> String:
	return "?" if kb < 0 else "%dM" % (kb / 1024)


## Температура (°C): батарея и первая доступная термозона. На многих телефонах закрыто — тогда «?».
static func _temp() -> String:
	var out := ""
	for p in ["/sys/class/power_supply/battery/temp", "/sys/class/thermal/thermal_zone0/temp"]:
		var f := FileAccess.open(p, FileAccess.READ)
		var s := "?"
		if f:
			var v := f.get_line().strip_edges()
			if v.is_valid_int():
				var t := int(v)
				# батарея отдаёт десятые доли градуса, термозоны — тысячные
				s = str(t / 10) if t < 1500 else str(t / 1000)
		out += ("/" if out != "" else "") + s
	return out


## Строка от движка: общий лимит, без повторов подряд, в файл не чаще раза в секунду (ошибки — сразу).
func log_note(text: String) -> void:
	_log_lines += 1
	if _log_lines > 80:
		return
	if not _lines.is_empty() and _lines[_lines.size() - 1].ends_with(text):
		return
	_add(text)
	if text.begins_with("ERR"):
		_flush()
	else:
		_dirty = true


# --- Android: память процесса и тепловой статус через Java (на HarmonyOS /proc закрыт)
var _jdebug = null
var _jpower = null
var _java_tried := false


func _java_init() -> void:
	_java_tried = true
	if OS.get_name() != "Android" or not Engine.has_singleton("JavaClassWrapper"):
		return
	var jcw = Engine.get_singleton("JavaClassWrapper")
	_jdebug = jcw.wrap("android.os.Debug")
	if Engine.has_singleton("AndroidRuntime"):
		var act = Engine.get_singleton("AndroidRuntime").getActivity()
		if act:
			_jpower = act.getSystemService("power")


## «PSS=…M куча=…M тепло=…» или пусто. Тепловой статус Android: 0 нет, 1 лёгкий, 2 умеренный,
## 3 сильный, 4 критический, 5 аварийный, 6 отключение.
func _android_stats() -> String:
	if not _java_tried:
		_java_init()
	var out := ""
	if _jdebug:
		var pss = _jdebug.getPss()
		var heap = _jdebug.getNativeHeapAllocatedSize()
		if pss != null:
			out += " PSS=%dM" % (int(pss) / 1024)
		if heap != null:
			out += " куча=%dM" % (int(heap) / 1048576)
	if _jpower:
		var th = _jpower.getCurrentThermalStatus()
		if th != null:
			out += " тепло=%d" % int(th)
	return out


## Событие игры (прицел, граната, смерть…) — чтобы видеть, что происходило перед вылетом.
func event(text: String) -> void:
	_add("> " + text)
	_dirty = true


func note(text: String) -> void:
	_add(text)
	_flush()


func _add(text: String) -> void:
	var s := "%4ds %s" % [(Time.get_ticks_msec() - _start_ms) / 1000, text]
	_lines.append(s)
	if not _skip_log:
		_log_raw(s)
	if _lines.size() > KEEP:
		_lines = _lines.slice(_lines.size() - KEEP)


func _flush(tail := "") -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + ("\n" + tail if tail != "" else ""))
		f.close()


func _process(delta: float) -> void:
	# отправка прошлых журналов — когда игра уже загрузилась и работает (по реальному времени)
	if not _upload_started and Time.get_ticks_msec() - _start_ms > 8000:
		_upload_started = true
		_uploader.run()
	_t += delta
	_flush_t += delta
	if _dirty and _flush_t > 1.0:
		_flush_t = 0.0
		_dirty = false
		_flush()
	if _t < 2.0:
		return
	_t = 0.0
	_tick += 1
	var state := "меню"
	var extra := ""
	if Game.playing and is_instance_valid(Game.player):
		state = "пауза" if get_tree().paused else "бой"
		var pp: Vector3 = Game.player.global_position
		extra = " поз=(%d,%d,%d) карта=%d" % [pp.x, pp.y, pp.z, int(Settings.data.map)]
		var alive := 0
		for e in Game.enemies:
			if is_instance_valid(e) and e.alive():
				alive += 1
		extra += " враги=%d пули=%d hp=%d" % [alive, Game.ballistics.bullets.size() if Game.ballistics else -1, int(Game.player.hp)]
	_skip_log = _tick % LOG_EVERY != 1
	# время кадра: логика и физика (Godot), подготовка и отрисовка на процессоре, на видеочипе (если драйвер отдаёт)
	var vrid := get_viewport().get_viewport_rid()
	if not _measure_on:
		RenderingServer.viewport_set_measure_render_time(vrid, true)
		_measure_on = true
	var tms := " мс: кадр=%.1f физ=%.1f рендерЦП=%.1f ГП=%.1f" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(vrid)]
	var aa := "FXAA" if Settings.fxaa_on() else "нет"
	if get_viewport().msaa_3d != Viewport.MSAA_DISABLED:
		aa = "MSAA%d" % (2 << (get_viewport().msaa_3d - 1))
	note("%s fps=%d игра=%s видео=%.0fM своб=%s t=%s масштаб=%.2f/%.2f сглаж=%s узлы=%d объекты=%d draw=%d тр=%dk%s" % [
		state, Engine.get_frames_per_second(),
		_mb_kb(_proc_kb("/proc/self/status", "VmRSS")),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		_mb_kb(_meminfo("MemAvailable")), _temp(), Settings.dyn_scale, get_viewport().scaling_3d_scale, aa,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000, extra + tms + _android_stats()])
	_skip_log = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			if not _paused:
				_paused = true
				note("СВЁРНУТО")
		NOTIFICATION_APPLICATION_RESUMED:
			if _paused:
				_paused = false
				note("РАЗВЁРНУТО")
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			_flush("EXIT")
			if _slog:
				_log_raw("EXIT")
				_slog = null
		NOTIFICATION_OS_MEMORY_WARNING:
			note("!!! СИСТЕМА: МАЛО ПАМЯТИ")


## Полный текст отчёта: прошлый запуск (если был аварийным) + текущий.
func full_report() -> String:
	var s := "Операция Гранит, отчёт %s\n" % Time.get_datetime_string_from_system(false, true)
	if FileAccess.file_exists(PREV):
		var how := "штатно"
		if prev_crashed:
			how = "после сворачивания" if prev_was_paused else "аварийно"
		s += "\n=== ПРОШЛЫЙ ЗАПУСК (завершился %s) ===\n%s\n" % [how, FileAccess.get_file_as_string(PREV)]
	s += "\n=== ТЕКУЩИЙ ЗАПУСК ===\n%s\n" % "\n".join(_lines)
	return s


## Сохраняет отчёт в «Загрузки» (на ПК — в папку данных игры) и копирует в буфер обмена.
## Возвращает текст для пользователя: куда сохранено.
func export_report() -> String:
	var text := full_report()
	DisplayServer.clipboard_set(text)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var fname := "GranitOps_report_%s.txt" % stamp
	var dirs: Array[String] = []
	if OS.get_name() == "Android":
		dirs.append(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))
		dirs.append("/storage/emulated/0/Download")
		dirs.append(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	dirs.append(OS.get_user_data_dir())
	for d in dirs:
		if d == "":
			continue
		var f := FileAccess.open(d.path_join(fname), FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
			if d == OS.get_user_data_dir() and OS.get_name() == "Android":
				# внутренняя папка приложения недоступна пользователю — честно говорим про буфер
				break
			return "Сохранено: %s\nТекст также скопирован в буфер обмена." % d.path_join(fname)
	return "Отчёт скопирован в буфер обмена — вставьте его в сообщение (в общую папку телефона файл записать не удалось)."


## PSS процесса в МБ (-1, если недоступно).
func pss_mb() -> int:
	if not _java_tried:
		_java_init()
	if _jdebug == null:
		return -1
	var v = _jdebug.getPss()
	return -1 if v == null else int(v) / 1024
