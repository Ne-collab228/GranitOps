extends Node
## Настройки игры: графика, управление, звук. Автозагрузка "Settings".

signal changed

const PATH := "user://settings.cfg"
const OVERRIDE := "user://override.cfg"

const VERSION := 5
const PRESETS := [
	{"name": "Низкое", "scale": 0.9, "shadows": 1, "aa": 1, "glow": false, "normal_maps": false, "veg": 0, "ssao": false, "draw": 0.8, "lod": 3.0},
	{"name": "Среднее", "scale": 1.0, "shadows": 2, "aa": 1, "glow": false, "normal_maps": true, "veg": 1, "ssao": false, "draw": 0.9, "lod": 2.0},
	{"name": "Высокое", "scale": 1.0, "shadows": 3, "aa": 1, "glow": true, "normal_maps": true, "veg": 2, "ssao": false, "draw": 1.0, "lod": 1.0},
	{"name": "Ультра", "scale": 1.0, "shadows": 4, "aa": 1, "glow": true, "normal_maps": true, "veg": 2, "ssao": true, "draw": 1.0, "lod": 1.0},
]
## Ниже этого масштаба картинка превращается в «мыло» и вдали не видно противников.
## 1.8: после разгрузки сцены (тени, склейка, интерфейс) поднято с 0.7 — FPS от разрешения зависит слабо.
const MIN_SCALE := 0.8
## Предел высоты 3D-картинки в пикселях по пресету (0 — без предела). На телефоне с экраном 2400x1080
## масштаб 0.8 давал 1920x864 — слабому GPU это не по силам; 720 строк на 6" экране выглядят чётко.
const MAX_H := [720, 864, 1080, 0]
const SHADOW_SIZE := [0, 1024, 2048, 2048, 4096]
## Тени только вблизи: каждый слой теней заново рисует всё, что в него попало, а на слабом телефоне
## упор именно в число вызовов отрисовки. Дальше этой границы — только затенение у земли (цвет вершин).
const SHADOW_DIST := [0.0, 25.0, 40.0, 60.0, 120.0]

var is_mobile := false
var touch_ui := false
var is_rd := false
var gpu_name := ""

var data := {
	"quality": 2, "scale": 1.0, "shadows": 3, "aa": 1, "glow": true, "normal_maps": true,
	"veg": 2, "ssao": false, "draw": 1.0, "lod": 1.0,
	"dyn_res": false, "fps_cap": 0, "show_fps": false, "send_logs": true,
	"sens": 1.0, "ads_sens": 0.75, "invert_y": false, "gyro": false, "aim_assist": true,
	"auto_fire": false, "left_fire": true, "toggle_ads": true, "vibration": true,
	"fov": 75.0, "volume": 0.9, "difficulty": 1, "renderer": "auto",
	"marks": true, "map": 0, "loadout": {}, "ver": 0, "thermal_bh": false,
	# расположение сенсорных кнопок: id -> [x доля ширины, y доля высоты, масштаб]; "stick" — джойстик
	"btn_layout": {}, "btn_alpha": 1.0,
}

var dyn_scale := 1.0
## Тест памяти: временно выключить FXAA, не трогая сохранённые настройки.
var aa_test_off := false
var _fxaa_layer: CanvasLayer
var _fxaa_rect: ColorRect
var _dyn_t := 0.0
var _dyn_good := 0
var _dyn_bad := 0
var _dyn_cool := 0.0


func _enter_tree() -> void:
	is_mobile = OS.has_feature("mobile")
	touch_ui = is_mobile or "--touch" in OS.get_cmdline_user_args()
	is_rd = RenderingServer.get_rendering_device() != null
	gpu_name = RenderingServer.get_video_adapter_name()
	var first := not FileAccess.file_exists(PATH)
	if first:
		set_preset(_auto_quality())
		if is_mobile:
			data.dyn_res = true
			# 60 FPS слабый телефон не держит: GPU работает на пределе, перегревается, динамическое
			# разрешение сидит на минимуме. Ровные 30 кадров и запас по нагреву лучше.
			data.fps_cap = 30
			data.difficulty = 0
	else:
		_load()
		if int(data.ver) < 2:
			# старые настройки давали слишком низкое разрешение рендера — пересчитать пресет
			set_preset(maxi(int(data.quality), 1) if is_mobile else int(data.quality))
		if int(data.ver) < 3 and is_mobile:
			set_preset(mini(int(data.quality), _auto_quality()))
			data.dyn_res = true
			if int(data.fps_cap) == 0 or int(data.fps_cap) > 30:
				data.fps_cap = 30
		if int(data.ver) < 5:
			# новые пресеты рендерят чётче (низкое 0.9, среднее 1.0) — не ниже значения своего пресета
			data.scale = maxf(float(data.scale), float(PRESETS[clampi(int(data.quality), 0, 3)].scale))
		if int(data.ver) < 4:
			# MSAA на Mali (GLES3) течёт ~0.8 МБ за кадр (тест памяти 1.6) — заменён своим FXAA
			data.aa = 1
	data.ver = VERSION
	# миграции могли поменять масштаб — динамическое разрешение начинает с него
	dyn_scale = float(data.scale)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preset="):
			set_preset(int(a.get_slice("=", 1)))
			data.dyn_res = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply()
	if not FileAccess.file_exists(PATH):
		save()


func _auto_quality() -> int:
	if not is_mobile:
		var g := gpu_name.to_lower()
		if g.contains("intel") or not is_rd:
			return 1
		return 2
	var gpu := gpu_name.to_lower()
	for weak in ["mali-g5", "mali-g3", "mali-t", "powervr", "adreno (tm) 5", "adreno (tm) 60", "adreno (tm) 61", "mali-4", "sc7731", "videocore"]:
		if gpu.contains(weak):
			return 0
	for strong in ["adreno (tm) 7", "adreno (tm) 8", "mali-g7", "mali-g61", "mali-g71", "immortalis", "xclipse", "apple"]:
		if gpu.contains(strong):
			return 2
	return 1 if OS.get_processor_count() >= 8 else 0


func set_preset(q: int) -> void:
	q = clampi(q, 0, PRESETS.size() - 1)
	data.quality = q
	for k in PRESETS[q]:
		if k != "name":
			data[k] = PRESETS[q][k]
	dyn_scale = data.scale


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in data:
		data[k] = cf.get_value("s", k, data[k])
	dyn_scale = data.scale


func save() -> void:
	var cf := ConfigFile.new()
	for k in data:
		cf.set_value("s", k, data[k])
	cf.save(PATH)


## Выбор рендера на телефоне применяется после перезапуска (через override.cfg).
func set_renderer(mode: String) -> void:
	data.renderer = mode
	if mode == "auto":
		if FileAccess.file_exists(OVERRIDE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE))
	else:
		var cf := ConfigFile.new()
		cf.set_value("rendering", "renderer/rendering_method.mobile", mode)
		cf.set_value("rendering", "renderer/rendering_method", mode)
		cf.save(OVERRIDE)
	save()


func apply() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	dyn_scale = clampf(dyn_scale, minf(MIN_SCALE, data.scale), data.scale)
	if not data.dyn_res:
		dyn_scale = data.scale
	_apply_scale(vp)
	# MSAA в мобильном рендере (GLES3) на Mali-G52 утекает ~0.8 МБ нативной памяти за кадр
	# (тест памяти 1.6: после ошибки создания буфера MSAA рост прекратился). Только свой FXAA.
	vp.msaa_3d = Viewport.MSAA_DISABLED
	_ensure_fxaa()
	vp.mesh_lod_threshold = data.lod
	if "anisotropic_filtering_level" in vp:
		vp.set("anisotropic_filtering_level", clampi(data.quality + 2, 2, 4))
	# резче текстуры вдали (особенно при масштабе рендера ниже 100%)
	vp.texture_mipmap_bias = -0.6 if dyn_scale < 0.95 else -0.3
	var sh: int = clampi(data.shadows, 0, 4)
	if sh > 0:
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZE[sh], true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh])
	# пока 3D заморожено (меню/пауза) — свой предел 30 кадров
	Engine.max_fps = 30 if vp.disable_3d else int(data.fps_cap)
	# при 30 кадрах физика 60 Гц считала бы по два шага на кадр; враги интерполируются, игрок двигается в _process
	Engine.physics_ticks_per_second = 30 if (is_mobile and int(data.fps_cap) > 0 and int(data.fps_cap) <= 30) else 60
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, data.volume)))
	changed.emit()


## FXAA: встроенный в Godot работает только в Forward+/Mobile, а на телефоне — OpenGL (Compatibility).
## Поэтому свой проход: прямоугольник на весь экран под интерфейсом читает готовую 3D-картинку.
## Источник передаётся в fx(): для экрана — экранная текстура, для витрины оружейной — TEXTURE контейнера.
const FXAA_TEMPLATE := "
shader_type canvas_item;
render_mode unshaded;
SRC_DECL
// смешиваем в premultiplied alpha: у витрины прозрачный фон, иначе по контуру светлая кайма
vec4 premul(vec4 c) {
	float a = ALPHA_SRC;
	return vec4(c.rgb * a, a);
}
#define SMP(p) premul(textureLod(SRC, p, 0.0))
void fragment() {
	vec2 uv = UV_SRC;
	vec2 px = PX_SRC;
	vec4 cM = SMP(uv);
	vec4 cNW = SMP(uv + vec2(-1.0, -1.0) * px);
	vec4 cNE = SMP(uv + vec2(1.0, -1.0) * px);
	vec4 cSW = SMP(uv + vec2(-1.0, 1.0) * px);
	vec4 cSE = SMP(uv + vec2(1.0, 1.0) * px);
	const vec3 W = vec3(0.299, 0.587, 0.114);
	float lM = dot(cM.rgb, W);
	float lNW = dot(cNW.rgb, W);
	float lNE = dot(cNE.rgb, W);
	float lSW = dot(cSW.rgb, W);
	float lSE = dot(cSE.rgb, W);
	float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
	float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));
	vec4 r = cM;
	// плоские участки не трогаем: и быстрее, и текстуры не мылятся
	if (lMax - lMin >= max(0.04, lMax * 0.15)) {
		vec2 dir = vec2(-((lNW + lNE) - (lSW + lSE)), (lNW + lSW) - (lNE + lSE));
		float reduce = max((lNW + lNE + lSW + lSE) * 0.03125, 1.0 / 128.0);
		float rcp = 1.0 / (min(abs(dir.x), abs(dir.y)) + reduce);
		dir = clamp(dir * rcp, vec2(-8.0), vec2(8.0)) * px;
		vec4 a = 0.5 * (SMP(uv + dir * (1.0 / 3.0 - 0.5)) + SMP(uv + dir * (2.0 / 3.0 - 0.5)));
		vec4 b = a * 0.5 + 0.25 * (SMP(uv - dir * 0.5) + SMP(uv + dir * 0.5));
		float lB = dot(b.rgb, W);
		r = (lB < lMin || lB > lMax) ? a : b;
	}
	COLOR = r.a > 0.0001 ? vec4(r.rgb / r.a, r.a) : vec4(0.0);
}
"


## Встроенную текстуру (TEXTURE) нельзя передавать в функцию — часть компиляторов шейдеров Godot
## на этом ругается, поэтому источник подставляется текстом через #define.
static func fxaa_shader(screen: bool) -> Shader:
	var code := FXAA_TEMPLATE
	if screen:
		# у экрана прозрачности нет: альфу не читаем
		code = code.replace("SRC_DECL", "uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;")
		code = code.replace("ALPHA_SRC", "1.0").replace("UV_SRC", "SCREEN_UV").replace("PX_SRC", "SCREEN_PIXEL_SIZE")
		code = code.replace("textureLod(SRC,", "textureLod(screen_tex,")
	else:
		code = code.replace("SRC_DECL", "").replace("ALPHA_SRC", "c.a").replace("UV_SRC", "UV").replace("PX_SRC", "TEXTURE_PIXEL_SIZE")
		code = code.replace("textureLod(SRC,", "textureLod(TEXTURE,")
	var sh := Shader.new()
	sh.code = code
	return sh


func _ensure_fxaa() -> void:
	if _fxaa_layer != null:
		return
	# под всеми слоями интерфейса (HUD — 5, меню — 0), но над «замороженным» кадром (−10)
	_fxaa_layer = CanvasLayer.new()
	_fxaa_layer.layer = -5
	_fxaa_rect = ColorRect.new()
	_fxaa_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fxaa_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = fxaa_shader(true)
	_fxaa_rect.material = m
	_fxaa_layer.add_child(_fxaa_rect)
	add_child(_fxaa_layer)


func fxaa_on() -> bool:
	return _fxaa_layer != null and _fxaa_layer.visible


func _apply_scale(vp: Viewport) -> void:
	var s := dyn_scale * height_cap()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (is_rd and s < 0.99) else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


func height_cap() -> float:
	var mh: int = MAX_H[clampi(int(data.quality), 0, MAX_H.size() - 1)]
	var h := DisplayServer.window_get_size().y
	if mh <= 0 or h <= mh or not is_mobile:
		return 1.0
	return float(mh) / float(h)


## Строка настроек графики для отчёта (по ней видно, на каком пресете играли).
func summary() -> String:
	var q := int(data.quality)
	var d := data
	return "настройки: пресет=%s тени=%d сглаж=%s свечение=%s нормали=%s трава=%d дальность=%.1f масштаб=%.2f дин=%s кап=%d" % [
		PRESETS[clampi(q, 0, 3)].name, int(d.shadows), "FXAA" if int(d.aa) > 0 else "нет", "вкл" if d.glow else "выкл",
		"вкл" if d.normal_maps else "выкл", int(d.veg), float(d.draw), float(d.scale), "вкл" if d.dyn_res else "выкл", int(d.fps_cap)]


func shadow_distance() -> float:
	return SHADOW_DIST[clampi(data.shadows, 0, 4)]


## Динамическое разрешение: держим целевой FPS, меняя масштаб 3D-рендера.
func _process(delta: float) -> void:
	if _fxaa_layer:
		# в меню/на паузе 3D заморожено — там сглаживать нечего
		_fxaa_layer.visible = int(data.aa) > 0 and not aa_test_off and not get_viewport().disable_3d
	if not data.dyn_res or get_viewport().disable_3d:
		return
	_dyn_t += delta
	_dyn_cool -= delta
	if _dyn_t < 1.0:
		return
	_dyn_t = 0.0
	# Каждая смена масштаба пересоздаёт все буферы 3D-рендера; на Mali частые пересоздания
	# (при нагреве FPS скачет) копят память драйвера и роняют игру. Поэтому крупные шаги и пауза 8 с.
	if _dyn_cool > 0.0:
		return
	var target := float(data.fps_cap)
	if target <= 0.0:
		target = DisplayServer.screen_get_refresh_rate()
		if target <= 0.0:
			target = 60.0
	var fps := Engine.get_frames_per_second()
	var old := dyn_scale
	if fps < target * 0.86:
		_dyn_bad += 1
		if _dyn_bad >= 3:
			dyn_scale = maxf(minf(MIN_SCALE, data.scale), dyn_scale - 0.1)
			_dyn_bad = 0
		_dyn_good = 0
	elif fps >= target * 0.96:
		_dyn_bad = 0
		_dyn_good += 1
		if _dyn_good >= 10 and dyn_scale < data.scale:
			dyn_scale = minf(data.scale, dyn_scale + 0.1)
			_dyn_good = 0
	else:
		_dyn_good = 0
		_dyn_bad = 0
	if not is_equal_approx(old, dyn_scale):
		_dyn_cool = 8.0
		if has_node("/root/Blackbox"):
			get_node("/root/Blackbox").note("масштаб %.2f -> %.2f (fps %d)" % [old, dyn_scale, fps])
		_apply_scale(get_viewport())
