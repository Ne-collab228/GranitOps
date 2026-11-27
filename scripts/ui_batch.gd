class_name UiBatch
extends RefCounted
## Пакетная отрисовка интерфейса боя. В Compatibility-рендере каждый круг, дуга, многоугольник
## и каждая смена текстуры (прямоугольник ↔ текст, разные размеры шрифта) — отдельный вызов отрисовки:
## интерфейс с сенсорными кнопками стоил ~100 вызовов, столько же, сколько вся 3D-сцена.
## Здесь всё складывается в очереди и выводится группами: картинки из одного атласа (прямоугольники,
## круги, кольца, треугольники, значки кнопок) → косые линии → прочие фигуры → весь текст
## (MSDF-шрифт: все размеры и обводка в одной текстуре). Итого 3–4 вызова на слой интерфейса.
## Пока атлас не готов (первые кадры) — рисуется напрямую, как раньше.

const SLOT := 128
const COLS := 4
## Кольца в атласе: толщина / радиус (ряд ×1.44 — при выборе ближайшего ошибка толщины не больше ±20%).
## Внешний край каждого кольца — радиус RING_OUT в слоте.
const RING_RATIOS := [0.022, 0.032, 0.046, 0.066, 0.095, 0.14]
const RING_OUT := 60.0
const ICON_S := 1.4
const SPRITES := ["disc", "ring0", "ring1", "ring2", "ring3", "ring4", "ring5", "tri_down", "tri_up",
	"fire", "ads", "jump", "crouch", "reload", "switch", "grenade", "heal", "pause", "interact"]

static var atlas: Texture2D
static var regions := {}
static var _building := false
static var _msdf_font: Font

var c: Control
var font: Font
var _quads: Array = []
var _lines: Array = []
var _prims: Array = []
var _texts: Array = []


static func ring_center_r(i: int) -> float:
	return RING_OUT / (1.0 + float(RING_RATIOS[i]) * 0.5)


class Painter extends Control:
	func _draw() -> void:
		for i in SPRITES.size():
			var o := Vector2((i % COLS) * SLOT, (i / COLS) * SLOT)
			var ctr := o + Vector2(SLOT, SLOT) * 0.5
			var w := Color.WHITE
			var p := 4.0
			match String(SPRITES[i]):
				"disc":
					draw_circle(ctr, SLOT * 0.5 - p, w)
				"ring0", "ring1", "ring2", "ring3", "ring4", "ring5":
					var ri := int(String(SPRITES[i]).substr(4))
					var rc := UiBatch.ring_center_r(ri)
					draw_arc(ctr, rc, 0.0, TAU, 96, w, rc * float(RING_RATIOS[ri]), true)
				"tri_down":
					draw_colored_polygon(PackedVector2Array([o + Vector2(SLOT * 0.5, SLOT - p), o + Vector2(p, p), o + Vector2(SLOT - p, p)]), w)
				"tri_up":
					draw_colored_polygon(PackedVector2Array([o + Vector2(SLOT * 0.5, p), o + Vector2(p, SLOT - p), o + Vector2(SLOT - p, SLOT - p)]), w)
				_:
					TouchControls.paint_icon(self, String(SPRITES[i]), ctr, ICON_S, w, ICON_S)


## Один раз за запуск игры рисует атлас в SubViewport и сохраняет текстурой.
static func ensure(host: Node) -> void:
	if atlas != null or _building:
		return
	_building = true
	var vp := SubViewport.new()
	vp.size = Vector2i(SLOT * COLS, SLOT * ceili(float(SPRITES.size()) / COLS))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Фон — белый прозрачный (без смешивания), фигуры — белые в режиме premultiplied alpha:
	# цвет везде остаётся белым (иначе край темнеет — цвет умножается на альфу), форму несёт альфа.
	# Так не нужен попиксельный цикл по атласу (0.2–0.5 с на телефоне).
	var bg := ColorRect.new()
	bg.size = Vector2(vp.size)
	var bgm := ShaderMaterial.new()
	var bgs := Shader.new()
	bgs.code = "shader_type canvas_item;
render_mode blend_disabled;
void fragment() { COLOR = vec4(1.0, 1.0, 1.0, 0.0); }"
	bgm.shader = bgs
	bg.material = bgm
	vp.add_child(bg)
	var pnt := Painter.new()
	pnt.size = Vector2(vp.size)
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	pnt.material = pm
	vp.add_child(pnt)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		_building = false
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		_building = false
		return
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	for i in SPRITES.size():
		var o := Vector2((i % COLS) * SLOT, (i / COLS) * SLOT)
		regions[SPRITES[i]] = Rect2(o, Vector2(SLOT, SLOT))
	# белый пиксель для прямоугольников — середина диска
	regions["white"] = Rect2(Vector2(SLOT * 0.5 - 2.0, SLOT * 0.5 - 2.0), Vector2(4, 4))
	atlas = ImageTexture.create_from_image(img)
	_building = false


## Шрифт интерфейса: MSDF (одна текстура на все размеры и обводку), если текстовый сервер умеет.
static func hud_font() -> Font:
	if _msdf_font:
		return _msdf_font
	var base := ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	if base is FontFile and ts and ts.has_feature(TextServer.FEATURE_FONT_MSDF):
		var ff := (base as FontFile).duplicate() as FontFile
		ff.multichannel_signed_distance_field = true
		ff.msdf_pixel_range = 16
		ff.msdf_size = 48
		# Глифы заранее НЕ строим: render_range раскладывает их по нескольким текстурам кэша,
		# и текст снова рвёт пакет (+90 вызовов отрисовки, проверено замером).
		_msdf_font = ff
	else:
		_msdf_font = base
	return _msdf_font


static func is_msdf(f: Font) -> bool:
	return f is FontFile and (f as FontFile).multichannel_signed_distance_field


func begin(target: Control, f: Font) -> void:
	c = target
	font = f
	_quads.clear()
	_lines.clear()
	_prims.clear()
	_texts.clear()


func ready() -> bool:
	return atlas != null


func _quad(region: String, r: Rect2, col: Color) -> void:
	_quads.append([r, regions[region], col])


func draw_rect(r: Rect2, col: Color, filled := true, width := 1.0) -> void:
	if not ready():
		c.draw_rect(r, col, filled, width if not filled else -1.0)
		return
	r = r.abs()
	if filled:
		_quad("white", r, col)
		return
	var h := width * 0.5
	_quad("white", Rect2(r.position.x - h, r.position.y - h, r.size.x + width, width), col)
	_quad("white", Rect2(r.position.x - h, r.end.y - h, r.size.x + width, width), col)
	_quad("white", Rect2(r.position.x - h, r.position.y + h, width, r.size.y - width), col)
	_quad("white", Rect2(r.end.x - h, r.position.y + h, width, r.size.y - width), col)


func draw_line(a: Vector2, b: Vector2, col: Color, width := 1.0) -> void:
	if not ready():
		c.draw_line(a, b, col, width)
		return
	var h := maxf(width, 1.0) * 0.5
	if is_equal_approx(a.y, b.y):
		_quad("white", Rect2(minf(a.x, b.x), a.y - h, absf(b.x - a.x), h * 2.0), col)
	elif is_equal_approx(a.x, b.x):
		_quad("white", Rect2(a.x - h, minf(a.y, b.y), h * 2.0, absf(b.y - a.y)), col)
	else:
		_lines.append([a, b, col, width])


func draw_circle(ctr: Vector2, r: float, col: Color) -> void:
	if not ready():
		c.draw_circle(ctr, r, col)
		return
	if r <= 2.5:
		# точка прицела / мил-точка: диск 120 px, уменьшенный в 30 раз, расплывается — квадратик чётче
		_quad("white", Rect2(ctr - Vector2(r, r), Vector2(r, r) * 2.0), col)
		return
	# диск в атласе — радиус SLOT/2 − 4 на слот SLOT: масштаб так, чтобы край совпал
	var k := r / (SLOT * 0.5 - 4.0)
	_quad("disc", Rect2(ctr - Vector2(SLOT, SLOT) * 0.5 * k, Vector2(SLOT, SLOT) * k), col)


func draw_arc(ctr: Vector2, r: float, a0: float, a1: float, segs: int, col: Color, width := 1.0) -> void:
	if ready() and absf(a1 - a0) >= TAU - 0.01:
		# полное кольцо — спрайт с ближайшим отношением толщина/радиус
		var want := width / maxf(r, 0.001)
		var best := 0
		for i in RING_RATIOS.size():
			if absf(log(float(RING_RATIOS[i]) / want)) < absf(log(float(RING_RATIOS[best]) / want)):
				best = i
		var k := r / ring_center_r(best)
		_quad("ring%d" % best, Rect2(ctr - Vector2(SLOT, SLOT) * 0.5 * k, Vector2(SLOT, SLOT) * k), col)
		return
	if not ready():
		c.draw_arc(ctr, r, a0, a1, segs, col, width)
		return
	_prims.append(["arc", ctr, r, a0, a1, segs, col, width])


func draw_colored_polygon(pts: PackedVector2Array, col: Color) -> void:
	if not ready():
		c.draw_colored_polygon(pts, col)
		return
	_prims.append(["poly", pts, col])


func draw_polyline(pts: PackedVector2Array, col: Color, width := 1.0) -> void:
	if not ready():
		c.draw_polyline(pts, col, width)
		return
	_prims.append(["polyline", pts, col, width])


## Треугольник-указатель (метка врага, метка задачи на компасе): вершиной вниз или вверх, вписан в r.
func tri(r: Rect2, col: Color, down := true, outline := Color(0, 0, 0, 0)) -> void:
	if not ready():
		var pts := PackedVector2Array([Vector2(r.get_center().x, r.end.y), r.position, Vector2(r.end.x, r.position.y)]) if down \
			else PackedVector2Array([Vector2(r.get_center().x, r.position.y), Vector2(r.position.x, r.end.y), r.end])
		c.draw_colored_polygon(pts, col)
		if outline.a > 0.0:
			pts.append(pts[0])
			c.draw_polyline(pts, outline, 1.0)
		return
	# обводка — тот же треугольник, на 1 px шире со всех сторон, под заливкой
	if outline.a > 0.0:
		_tri_quad(r.grow(1.0), outline, down)
	_tri_quad(r, col, down)


func _tri_quad(r: Rect2, col: Color, down: bool) -> void:
	# спрайт заполняет слот с полем 4 px — растягиваем на поле
	var k := r.size / Vector2(SLOT - 8.0, SLOT - 8.0)
	_quad("tri_down" if down else "tri_up", Rect2(r.position - Vector2(4, 4) * k, Vector2(SLOT, SLOT) * k), col)


## Значок сенсорной кнопки (без текста) радиуса r.
func icon(id: String, ctr: Vector2, r: float, col: Color) -> void:
	if not ready():
		TouchControls.paint_icon(c, id, ctr, r / 40.0, col, 1.0)
		return
	var key := "fire" if id == "fire2" else id
	if not regions.has(key):
		return
	var k := (r / 40.0) / ICON_S
	_quad(key, Rect2(ctr - Vector2(SLOT, SLOT) * 0.5 * k, Vector2(SLOT, SLOT) * k), col)


func text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_texts.append([pos, s, size, col, align, width])


func flush() -> void:
	for q in _quads:
		c.draw_texture_rect_region(atlas, q[0], q[1], q[2])
	for l in _lines:
		c.draw_line(l[0], l[1], l[2], l[3])
	for p in _prims:
		match String(p[0]):
			"arc":
				c.draw_arc(p[1], p[2], p[3], p[4], p[5], p[6], p[7])
			"poly":
				c.draw_colored_polygon(p[1], p[2])
			"polyline":
				c.draw_polyline(p[1], p[2], p[3])
	# обводки всех надписей, затем сами надписи: у MSDF-шрифта одна текстура — один вызов;
	# у обычного каждый размер — своя текстура, поэтому группируем по размеру
	var msdf := is_msdf(font)
	var order := _texts
	if not msdf:
		order = _texts.duplicate()
		order.sort_custom(func(a, b): return int(a[2]) < int(b[2]))
	var ow := 8 if msdf else 4
	for t in order:
		var col: Color = t[3]
		c.draw_string_outline(font, t[0], t[1], t[4], t[5], t[2], ow, Color(0, 0, 0, 0.75 * col.a))
	for t in order:
		c.draw_string(font, t[0], t[1], t[4], t[5], t[2], t[3])
	_quads.clear()
	_lines.clear()
	_prims.clear()
	_texts.clear()
