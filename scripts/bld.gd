class_name Bld
extends RefCounted
## Детализированные процедурные здания (постсоветский / ближневосточный посёлок): окна с рамами,
## стеклом, подоконниками и отливами, двери с коробкой, полотном, козырьком и крыльцом, цоколь,
## пояски, карниз, водостоки, кондиционеры, тарелки, балконы, крыши разных типов, интерьер.
##
## Всё пишется в переданный Geo (один меш на материал на весь Geo) — вызывающая карта сама решает,
## когда делать finish. Коллизии — простые коробки, тип поверхности берётся из материала
## (plaster/concrete не простреливаются, wood/iron/slate/roof_red — простреливаются).
##
## Локальные оси здания: pos — центр пятна на уровне земли, вход (главный фасад) смотрит в +Z,
## yaw — поворот вокруг Y. rng — свой генератор карты: одинаковые типы получаются разными.
## out — необязательный словарь для точек ИИ (массивы Vector3 в мировых координатах, ключи создаются сами):
##   "cover"  — укрытия снаружи (углы, крыльцо, забор);
##   "fire"   — позиции стрелков у окон внутри, на балконах и крыше (на уровне пола);
##   "doors"  — точки снаружи перед входами;
##   "inside" — центры помещений;
##   "roof"   — точки на доступной крыше.
## Каждая функция возвращает {"pos", "yaw", "w", "d", "floor_y", "top_y"} (высоты мировые).

## Палитры. Каждый материал — отдельный вызов отрисовки на весь Geo, поэтому карта может их сузить.
static var walls_house: Array = ["plaster_tan", "stucco_blue", "stucco_yellow", "concrete"]
static var walls_block: Array = ["concrete", "plaster_tan", "stucco_yellow"]
static var walls_east: Array = ["concrete", "plaster_tan"]
static var roofs: Array = ["slate", "roof_red", "iron"]

const DOOR_W := 1.2    # проём двери (просвет с коробкой ≥ 1.05)
const DOOR_H := 2.25   # высота проёма (просвет под коробкой ≥ 2.15)
const IDOOR_W := 1.15  # внутренние двери


static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return String(arr[rng.randi() % arr.size()])


## Треугольник с лицевой стороной по нормали n (в Godot лицевые — по часовой), UV — проекция на плоскость.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, u: Vector3) -> void:
	var pts := [a, b, c]
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [a, c, b]
	var v := n.cross(u)
	for p in pts:
		var pv: Vector3 = p
		st.set_normal(n)
		st.set_tangent(Plane(u, 1.0))
		st.set_uv(Vector2(pv.dot(u), -pv.dot(v)))
		st.add_vertex(pv)


static func _tri_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, n: Vector3, u: Vector3) -> void:
	var pts := [a, b, c]
	var uvs := [ua, ub, uc]
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [a, c, b]
		uvs = [ua, uc, ub]
	for i in 3:
		st.set_normal(n)
		st.set_tangent(Plane(u, 1.0))
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


# =====================================================================================
## Контекст одного здания: преобразование, материалы, корпус, проёмы и все помощники.
class B extends RefCounted:
	var g: Geo
	var rng: RandomNumberGenerator
	var xf: Transform3D
	var yaw := 0.0
	var out: Dictionary
	# корпус
	var w := 8.0
	var d := 6.0
	var th := 0.3            # толщина наружных стен
	var fh := 3.0            # высота этажа (от пола до пола)
	var floors := 1
	var floor_y := 0.4       # пол 1 этажа над землёй (цоколь)
	var parapet := 0.0       # парапет плоской крыши (0 — скатная)
	# материалы
	var wall := "plaster_tan"
	var trim := "concrete"   # пояски, карнизы, перемычки, подоконники
	var frame := "concrete"  # рамы окон
	var sill := "rust"       # отливы, водостоки (оцинковка)
	var leaf := "wood_dark"  # полотна наружных дверей
	var jamb := "wood_dark"  # дверные коробки
	var inner := "concrete"   # перегородки
	var floor_mat := "concrete"
	var plinth_mat := "concrete"
	var roof := "slate"
	var shut := "wood_dark"  # ставни
	var rail := "iron"       # ограждения балконов
	# детали
	var broken := 0.15       # доля выбитых окон
	var boarded := 0.07      # доля заколоченных
	var grilles := false     # решётки на окнах 1 этажа
	var shutters := false
	var nalich := ""         # наличники ("" — нет, тогда перемычка-бровка)
	var brow := 0.6          # вероятность бровки над окном без наличников
	var grime := 0.25        # вероятность подтёка под окном
	var soot := false        # копоть над окнами (руины)
	var canopy := 1          # козырёк над наружной дверью: 0 нет, 1 бетон, 2 лист на столбах, 3 лист на кронштейнах
	var ops := {}            # Vector2i(этаж, сторона) -> [[t0, t1, y0, y1, вид], ...]

	func _init(geo: Geo, r: RandomNumberGenerator, pos: Vector3, yw: float, o: Dictionary) -> void:
		g = geo
		rng = r
		yaw = yw
		xf = Transform3D(Basis(Vector3.UP, yw), pos)
		out = o

	# ------------------------------------------------------------- базовые помощники
	func pt(key: String, p: Vector3) -> void:
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(xf * p)

	func box(mat: String, c: Vector3, size: Vector3, collide := false, bas := Basis()) -> void:
		g.box_xf(mat, Transform3D(xf.basis * bas, xf * c), size, collide)

	func solid(mat: String, c: Vector3, size: Vector3, bas := Basis()) -> void:
		g.box_xf(mat, Transform3D(xf.basis * bas, xf * c), size, true)

	func col(kind: String, c: Vector3, size: Vector3, bas := Basis()) -> void:
		g.collider(kind, Transform3D(xf.basis * bas, xf * c), size)

	func cyl(mat: String, c: Vector3, r: float, h: float, segs := 6, bas := Basis(), r_top := -1.0, caps := true, collide := false) -> void:
		g.cyl(mat, Transform3D(xf.basis * bas, xf * c), r, h, segs, collide, caps, r_top)

	func stairs(mat: String, base: Vector3, yaw_l: float, width: float, rise: float, run: float) -> void:
		g.stairs(mat, xf * base, yaw + yaw_l, width, rise, run)

	func wall_ab(mat: String, a: Vector3, b2: Vector3, h: float, thick: float, o: Array = []) -> void:
		g.wall(mat, xf * a, xf * b2, h, thick, o)

	## Брус от p0 до p1 сечением sz (x — в вертикальной плоскости, y — поперёк).
	func bar(mat: String, p0: Vector3, p1: Vector3, sz: Vector2, collide := false) -> void:
		var ax := p1 - p0
		var ln := ax.length()
		if ln < 0.001:
			return
		var x := ax / ln
		var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.BACK
		var z := x.cross(up).normalized()
		var y := z.cross(x)
		box(mat, (p0 + p1) * 0.5, Vector3(ln, sz.x, sz.y), collide, Basis(x, y, z))

	## Труба (цилиндр) от p0 до p1.
	func tube(mat: String, p0: Vector3, p1: Vector3, r: float, segs := 6, r1 := -1.0) -> void:
		var ax := p1 - p0
		var ln := ax.length()
		if ln < 0.001:
			return
		var y := ax / ln
		var ref := Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT
		var x := ref.cross(y).normalized()
		var z := x.cross(y)
		cyl(mat, (p0 + p1) * 0.5, r, ln, segs, Basis(x, y, z), r1, false)

	## Плоский выпуклый многоугольник (точки по кругу, локально) с толщиной вдоль нормали.
	func slab(mat: String, pts: Array, nrm: Vector3, thick: float, uax: Vector3) -> void:
		var st: SurfaceTool = g._st(mat)
		var n := (xf.basis * nrm).normalized()
		var u := (xf.basis * uax).normalized()
		var off := nrm.normalized() * (thick * 0.5)
		var top: Array = []
		var bot: Array = []
		var cen := Vector3.ZERO
		for q in pts:
			var qv: Vector3 = q
			top.append(xf * (qv + off))
			bot.append(xf * (qv - off))
			cen += xf * qv
		cen /= float(pts.size())
		for i in range(1, pts.size() - 1):
			Bld._tri(st, top[0], top[i], top[i + 1], n, u)
			Bld._tri(st, bot[0], bot[i], bot[i + 1], -n, u)
		for i in pts.size():
			var j := (i + 1) % pts.size()
			var ti: Vector3 = top[i]
			var tj: Vector3 = top[j]
			var bi: Vector3 = bot[i]
			var bj: Vector3 = bot[j]
			var e := tj - ti
			if e.length() < 0.0001:
				continue
			var sn := e.cross(n).normalized()
			if sn.dot((ti + tj) * 0.5 - cen) < 0.0:
				sn = -sn
			Bld._tri(st, ti, tj, bj, sn, e.normalized())
			Bld._tri(st, ti, bj, bi, sn, e.normalized())

	## Наклейка грязи: region 0 — подтёки (тёмный верх), 1 — пятно; flip — тёмный низ (копоть над окном).
	func decal(c: Vector3, nrm: Vector3, right: Vector3, size: Vector2, region: int, flip := false) -> void:
		var st: SurfaceTool = g._st("grime")
		var n := (xf.basis * nrm).normalized()
		var r := (xf.basis * right).normalized()
		var up := n.cross(r)
		var cw := xf * c
		var u0 := 0.02 + 0.5 * region
		var u1 := u0 + 0.46
		if rng.randf() < 0.5:
			var tmp := u0
			u0 = u1
			u1 = tmp
		var v0 := 1.0 if flip else 0.0
		var v1 := 1.0 - v0
		var hx := r * size.x * 0.5
		var hy := up * size.y * 0.5
		var p0 := cw - hx + hy
		var p1 := cw + hx + hy
		var p2 := cw + hx - hy
		var p3 := cw - hx - hy
		Bld._tri_uv(st, p0, p1, p2, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), n, r)
		Bld._tri_uv(st, p0, p2, p3, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1), n, r)

	# ------------------------------------------------------------- корпус
	func yk(fl: int) -> float:
		return floor_y + fl * fh

	func top_y() -> float:
		return floor_y + floors * fh

	## Сторона: [a — начало оси стены (y=0), dir — вдоль стены, n — наружу, длина].
	## 0 — фасад (+Z), 1 — правая (+X), 2 — задняя (−Z), 3 — левая (−X).
	func side(i: int) -> Array:
		var hw := w * 0.5
		var hd := d * 0.5
		var ht := th * 0.5
		match i:
			0:
				return [Vector3(-hw, 0, hd - ht), Vector3.RIGHT, Vector3.BACK, w]
			1:
				return [Vector3(hw - ht, 0, hd - th), Vector3.FORWARD, Vector3.RIGHT, d - 2.0 * th]
			2:
				return [Vector3(hw, 0, -hd + ht), Vector3.LEFT, Vector3.FORWARD, w]
		return [Vector3(-hw + ht, 0, -hd + th), Vector3.BACK, Vector3.LEFT, d - 2.0 * th]

	## Координата здания (x для фасада/зада, z для боков) -> расстояние вдоль стены.
	func tof(si: int, v: float) -> float:
		match si:
			0:
				return v + w * 0.5
			1:
				return d * 0.5 - th - v
			2:
				return w * 0.5 - v
		return v + d * 0.5 - th

	func add_op(fl: int, si: int, o: Array) -> void:
		var k := Vector2i(fl, si)
		if not ops.has(k):
			ops[k] = []
		(ops[k] as Array).append(o)

	## Проём по координатам здания v0..v1 (x или z).
	func op_at(fl: int, si: int, v0: float, v1: float, y0: float, y1: float, kind: String) -> void:
		var a := tof(si, v0)
		var b2 := tof(si, v1)
		add_op(fl, si, [minf(a, b2), maxf(a, b2), y0, y1, kind])

	## n окон шириной ww равномерно на участке v0..v1 (если помещаются).
	func spread(fl: int, si: int, v0: float, v1: float, n: int, ww := 1.3, y0 := 0.85, y1 := 2.2, kind := "win") -> void:
		var lo := minf(v0, v1)
		var span := absf(v1 - v0)
		while n > 0 and span / n < ww + 0.5:
			n -= 1
		for i in n:
			var c := lo + span * (i + 0.5) / n
			op_at(fl, si, c - ww * 0.5, c + ww * 0.5, y0, y1, kind)

	## Монолитный цоколь под всем зданием (пол 1 этажа с коллизией) и чистовой пол.
	func base_slab(finish := true) -> void:
		var h := floor_y + 0.5
		solid(plinth_mat, Vector3(0, floor_y - h * 0.5, 0), Vector3(w + 0.06, h, d + 0.06))
		if finish:
			box(floor_mat, Vector3(0, floor_y + 0.005, 0), Vector3(w - 2.0 * th, 0.01, d - 2.0 * th))

	## Перекрытие (верх на высоте y) над прямоугольником; низ — потолок.
	func floor_rect(y: float, x0: float, x1: float, z0: float, z1: float, fin := "", thick := 0.2) -> void:
		var sx := absf(x1 - x0)
		var sz := absf(z1 - z0)
		if sx < 0.05 or sz < 0.05:
			return
		var c := Vector3((x0 + x1) * 0.5, y - thick * 0.5, (z0 + z1) * 0.5)
		solid("concrete", c, Vector3(sx, thick, sz))
		var f := fin if fin != "" else floor_mat
		if f != "-":
			box(f, Vector3(c.x, y + 0.005, c.z), Vector3(sx, 0.01, sz))

	## Перекрытие с одним вырезом (лестница).
	func floor_hole(y: float, x0: float, x1: float, z0: float, z1: float, hx0: float, hx1: float, hz0: float, hz1: float, fin := "") -> void:
		floor_rect(y, x0, x1, hz1, z1, fin)
		floor_rect(y, x0, x1, z0, hz0, fin)
		floor_rect(y, x0, hx0, hz0, hz1, fin)
		floor_rect(y, hx1, x1, hz0, hz1, fin)

	## Наружные стены по этажам с проёмами; затем обрамление всех проёмов.
	func walls() -> void:
		for fl in floors:
			var h := fh + (parapet if fl == floors - 1 else 0.0)
			for si in 4:
				var s := side(si)
				var a: Vector3 = s[0]
				var dir: Vector3 = s[1]
				var ln: float = s[3]
				var cut: Array = []
				for o in ops.get(Vector2i(fl, si), []):
					cut.append([o[0], o[1], o[2], o[3]])
				var y := yk(fl)
				wall_ab(wall, a + Vector3(0, y, 0), a + dir * ln + Vector3(0, y, 0), h, th, cut)
		for k in ops:
			var kk: Vector2i = k
			for o in ops[k]:
				dress(kk.x, kk.y, o)

	func dress(fl: int, si: int, o: Array) -> void:
		var s := side(si)
		var a: Vector3 = s[0]
		var dir: Vector3 = s[1]
		var n: Vector3 = s[2]
		var kind: String = o[4]
		var yb := yk(fl)
		var neigh: Array = ops.get(Vector2i(fl, si), [])
		match kind:
			"win":
				win_at(a, dir, n, th, o[0], o[1], yb + float(o[2]), yb + float(o[3]), fl == 0, neigh, s[3])
			"door", "bdoor":
				door_at(a, dir, n, th, o[0], o[1], yb + float(o[2]), yb + float(o[3]), leaf if kind == "door" else frame, kind == "bdoor")
				if kind == "door" and fl == 0:
					entrance(a, dir, n, o[0], o[1], yb + float(o[3]))

	# ------------------------------------------------------------- окна
	## Окно в стене: a/dir/n — ось стены, wt — толщина, t0..t1 — вдоль стены, y0..y1 — высоты.
	func win_at(a: Vector3, dir: Vector3, n: Vector3, wt: float, t0: float, t1: float, y0: float, y1: float,
			ground := false, neigh: Array = [], wall_len := 0.0) -> void:
		var bas := Basis(dir, Vector3.UP, n)
		var ww := t1 - t0
		var hh := y1 - y0
		var c := a + dir * ((t0 + t1) * 0.5)
		var ym := (y0 + y1) * 0.5
		var outer := wt * 0.5
		var fo := outer - minf(0.12, wt * 0.4)
		var r := rng.randf()
		var state := 0
		if r < boarded:
			state = 2
		elif r < boarded + broken:
			state = 1
		var fw := 0.065
		# рама с импостом и фрамугой (у выбитого окна — иногда без рамы)
		if state != 1 or rng.randf() < 0.55:
			box(frame, c + Vector3(0, y1 - fw * 0.5, 0) + n * fo, Vector3(ww, fw, 0.08), false, bas)
			box(frame, c + Vector3(0, y0 + fw * 0.5, 0) + n * fo, Vector3(ww, fw, 0.08), false, bas)
			box(frame, c + dir * (-ww * 0.5 + fw * 0.5) + Vector3(0, ym, 0) + n * fo, Vector3(fw, hh - 2.0 * fw, 0.08), false, bas)
			box(frame, c + dir * (ww * 0.5 - fw * 0.5) + Vector3(0, ym, 0) + n * fo, Vector3(fw, hh - 2.0 * fw, 0.08), false, bas)
			if ww > 0.95:
				box(frame, c + Vector3(0, ym, 0) + n * fo, Vector3(0.055, hh - 2.0 * fw, 0.06), false, bas)
			box(frame, c + Vector3(0, y0 + hh * 0.7, 0) + n * fo, Vector3(ww - 2.0 * fw, 0.05, 0.06), false, bas)
		if state == 0:
			box("glass", c + Vector3(0, ym, 0) + n * (fo - 0.01), Vector3(ww - 0.04, hh - 0.04, 0.012), false, bas)
		elif state == 1:
			# осколки в углах
			for k in rng.randi_range(1, 2):
				var sx := -1.0 if k == 0 else 1.0
				var sy := -1.0 if k == 0 else 1.0
				var corner := c + dir * (sx * (ww * 0.5 - fw)) + Vector3(0, ym + sy * (hh * 0.5 - fw), 0) + n * (fo - 0.01)
				var p1 := corner - dir * (sx * ww * rng.randf_range(0.2, 0.45))
				var p2 := corner - Vector3(0, sy * hh * rng.randf_range(0.2, 0.5), 0)
				slab("glass", [corner, p1, p2], n, 0.01, dir)
		else:
			for k in 3:
				var yy := y0 + hh * (0.2 + 0.3 * k) + rng.randf_range(-0.08, 0.08)
				box("wood", c + Vector3(0, yy, 0) + n * (outer + 0.025), Vector3(ww + 0.3, 0.16, 0.025), false,
					bas * Basis(Vector3.BACK, rng.randf_range(-0.22, 0.22)))
		# отлив снаружи и подоконник внутри
		var s0 := fo + 0.04
		var s1 := outer + 0.06
		box(sill, c + Vector3(0, y0 - 0.015, 0) + n * ((s0 + s1) * 0.5), Vector3(ww + 0.08, 0.025, s1 - s0), false,
			bas * Basis(Vector3.RIGHT, 0.15))
		var i0 := fo - 0.04
		var i1 := -outer - 0.07
		box(trim, c + Vector3(0, y0 - 0.02, 0) + n * ((i0 + i1) * 0.5), Vector3(ww + 0.12, 0.04, i0 - i1), false, bas)
		# наличники или бровка-перемычка
		if nalich != "":
			box(nalich, c + Vector3(0, y1 + 0.08, 0) + n * (outer + 0.02), Vector3(ww + 0.34, 0.16, 0.04), false, bas)
			for sd in [-1.0, 1.0]:
				box(nalich, c + dir * (sd * (ww * 0.5 + 0.06)) + Vector3(0, ym, 0) + n * (outer + 0.015), Vector3(0.12, hh, 0.03), false, bas)
		elif rng.randf() < brow:
			box(trim, c + Vector3(0, y1 + 0.06, 0) + n * (outer + 0.03), Vector3(ww + 0.24, 0.12, 0.06), false, bas)
		# решётка на первом этаже
		if ground and grilles and state != 2:
			var nb := maxi(3, int(ww / 0.16))
			for k in nb:
				var u := -ww * 0.5 + ww * (k + 0.5) / nb
				box("plate_dark", c + dir * u + Vector3(0, ym, 0) + n * (outer + 0.035), Vector3(0.022, hh + 0.08, 0.022), false, bas)
			for yy in [y0 + 0.1, y1 - 0.1, y0 + hh * 0.55]:
				box("plate_dark", c + Vector3(0, yy, 0) + n * (outer + 0.05), Vector3(ww + 0.08, 0.035, 0.012), false, bas)
		# ставни, если по бокам есть место
		elif shutters and state != 2 and _free(neigh, t0, t1, wall_len, ww * 0.5 + 0.12):
			var sw := ww * 0.5
			for sd in [-1.0, 1.0]:
				var b2 := bas
				var yy := ym
				if rng.randf() < 0.12:
					b2 = bas * Basis(Vector3.BACK, sd * 0.35)
					yy -= 0.12
				box(shut, c + dir * (sd * (ww * 0.5 + sw * 0.5 + 0.04)) + Vector3(0, yy, 0) + n * (outer + 0.02), Vector3(sw, hh, 0.03), false, b2)
		# подтёк под окном, копоть над ним
		if rng.randf() < grime:
			var ln := rng.randf_range(0.5, 1.4)
			decal(c + dir * rng.randf_range(-0.15, 0.15) + Vector3(0, y0 - 0.05 - ln * 0.5, 0) + n * (outer + 0.012), n, dir,
				Vector2(ww * rng.randf_range(0.6, 1.05), ln), 0)
		if soot or state == 1 and rng.randf() < 0.3:
			decal(c + Vector3(0, y1 + 0.55, 0) + n * (outer + 0.013), n, dir, Vector2(ww + 0.5, 1.3), 0, true)
		# стрелок у окна
		if y0 - _floor_below(y0) < 1.4:
			pt("fire", c - n * (outer + 0.7) + Vector3(0, _floor_below(y0), 0))

	func _floor_below(y: float) -> float:
		var fl := clampi(int(floor((y - floor_y + 0.05) / fh)), 0, maxi(floors - 1, 0))
		return yk(fl)

	## Есть ли по бокам проёма место шириной need (до соседних проёмов и концов стены).
	func _free(neigh: Array, t0: float, t1: float, wall_len: float, need: float) -> bool:
		if t0 < need + 0.1 or (wall_len > 0.0 and t1 > wall_len - need - 0.1):
			return false
		for o in neigh:
			var a0: float = o[0]
			var a1: float = o[1]
			if a0 == t0:
				continue
			if a1 <= t0 and t0 - a1 < need * 2.0 + 0.05:
				return false
			if a0 >= t1 and a0 - t1 < need * 2.0 + 0.05:
				return false
		return true

	# ------------------------------------------------------------- двери
	func door_at(a: Vector3, dir: Vector3, n: Vector3, wt: float, t0: float, t1: float, y0: float, y1: float,
			lmat: String, glazed := false, inner_wall := false) -> void:
		var bas := Basis(dir, Vector3.UP, n)
		var ww := t1 - t0
		var hh := y1 - y0
		var c := a + dir * ((t0 + t1) * 0.5)
		var jw := 0.05
		var jd := minf(wt + 0.02, 0.16)
		var fo := 0.0 if inner_wall else wt * 0.5 - jd * 0.5 - 0.03
		var jm := jamb if not glazed else frame
		box(jm, c + dir * (-ww * 0.5 + jw * 0.5) + Vector3(0, y0 + hh * 0.5, 0) + n * fo, Vector3(jw, hh, jd), false, bas)
		box(jm, c + dir * (ww * 0.5 - jw * 0.5) + Vector3(0, y0 + hh * 0.5, 0) + n * fo, Vector3(jw, hh, jd), false, bas)
		box(jm, c + Vector3(0, y1 - jw * 0.5, 0) + n * fo, Vector3(ww, jw, jd), false, bas)
		# полотно: открыто внутрь/наружу, выбито (лежит внутри) или его нет
		var lw := ww - 2.0 * jw - 0.02
		var lh := hh - jw - 0.03
		var r := rng.randf()
		var side_in := -1.0 if inner_wall and rng.randf() < 0.5 else 1.0
		if r < 0.78:
			var inward := r < 0.5 or glazed
			var ang := rng.randf_range(1.3, 1.57)
			var off := fo - jd * 0.5 if inward else fo + jd * 0.5
			if inner_wall:
				off = side_in * (wt * 0.5)
				inward = side_in > 0.0
			var lb := bas * Basis(Vector3.UP, ang if inward else -ang)
			var hinge := c + dir * (-ww * 0.5 + jw) + Vector3(0, y0 + 0.01 + lh * 0.5, 0) + n * off
			var lc := hinge + lb.x * (lw * 0.5) + lb.z * (0.03 if not inward else -0.03)
			if glazed:
				box(lmat, lc + Vector3(0, -lh * 0.3, 0), Vector3(lw, lh * 0.4, 0.05), false, lb)
				box(lmat, lc + Vector3(0, lh * 0.45, 0), Vector3(lw, lh * 0.1, 0.05), false, lb)
				box(lmat, lc + lb.x * (-lw * 0.5 + 0.04) + Vector3(0, lh * 0.2, 0), Vector3(0.08, lh * 0.5, 0.05), false, lb)
				box(lmat, lc + lb.x * (lw * 0.5 - 0.04) + Vector3(0, lh * 0.2, 0), Vector3(0.08, lh * 0.5, 0.05), false, lb)
				box("glass", lc + Vector3(0, lh * 0.2, 0), Vector3(lw - 0.16, lh * 0.5, 0.012), false, lb)
			else:
				box(lmat, lc, Vector3(lw, lh, 0.045), false, lb)
				box("plate_dark", lc + lb.x * (lw * 0.38) + Vector3(0, -0.1, 0) + lb.z * 0.035, Vector3(0.12, 0.03, 0.03), false, lb)
		elif r < 0.9 and not glazed:
			var p := c - n * (wt * 0.5 + 0.95) + Vector3(0, y0 + 0.025, 0)
			box(lmat, p, Vector3(lw, 0.045, lh), false, bas * Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)) * Basis(Vector3.RIGHT, 0.03))

	## Крыльцо (площадка + ступени с пандусом-коллизией), козырёк, точки у входа.
	func entrance(a: Vector3, dir: Vector3, n: Vector3, t0: float, t1: float, top: float, porch_w := 0.0) -> void:
		var bas := Basis(dir, Vector3.UP, n)
		var ww := t1 - t0
		var c := a + dir * ((t0 + t1) * 0.5)
		var outer := th * 0.5
		var rise := floor_y
		var pw := maxf(ww + 0.8, porch_w)
		var pd := 1.2 if rise > 0.3 else 0.0
		var run := 0.0
		if pd > 0.0:
			solid(plinth_mat, c + Vector3(0, (rise - 0.4) * 0.5, 0) + n * (outer + pd * 0.5), Vector3(pw, rise + 0.4, pd), bas)
		if rise > 0.03:
			var steps := int(ceil(rise / 0.18))
			run = maxf(0.4, steps * 0.3)
			var sy := atan2(n.x, n.z)
			stairs(plinth_mat, c + n * (outer + pd + run), sy, ww + 0.3, rise, run)
		var cy := top + 0.3
		var cd := maxf(pd, 0.9) + 0.25
		var cw := ww + 0.8
		match canopy:
			1:
				box("concrete", c + Vector3(0, cy, 0) + n * (outer + cd * 0.5), Vector3(cw, 0.12, cd), false, bas)
				for sd in [-1.0, 1.0]:
					bar("plate_dark", c + dir * (sd * (cw * 0.5 - 0.12)) + Vector3(0, cy - 0.55, 0) + n * (outer + 0.02),
						c + dir * (sd * (cw * 0.5 - 0.12)) + Vector3(0, cy - 0.06, 0) + n * (outer + cd - 0.12), Vector2(0.06, 0.05))
			2:
				box(roof, c + Vector3(0, cy + 0.12, 0) + n * (outer + cd * 0.5), Vector3(cw, 0.04, cd + 0.15), false, bas * Basis(Vector3.RIGHT, 0.22))
				for sd in [-1.0, 1.0]:
					box("wood_dark", c + dir * (sd * (cw * 0.5 - 0.06)) + Vector3(0, cy * 0.5, 0) + n * (outer + cd - 0.12), Vector3(0.1, cy, 0.1), false, bas)
				box("wood_dark", c + Vector3(0, cy - 0.04, 0) + n * (outer + cd - 0.12), Vector3(cw, 0.1, 0.1), false, bas)
			3:
				box(roof, c + Vector3(0, cy + 0.1, 0) + n * (outer + cd * 0.45), Vector3(cw, 0.04, cd), false, bas * Basis(Vector3.RIGHT, 0.3))
				for sd in [-1.0, 1.0]:
					bar("plate_dark", c + dir * (sd * (cw * 0.5 - 0.1)) + Vector3(0, cy - 0.45, 0) + n * (outer + 0.02),
						c + dir * (sd * (cw * 0.5 - 0.1)) + Vector3(0, cy, 0) + n * (outer + cd * 0.8), Vector2(0.05, 0.04))
		pt("doors", c + n * (outer + pd + run + 0.8))
		for sd in [-1.0, 1.0]:
			pt("cover", c + dir * (sd * (pw * 0.5 + 0.55)) + n * (outer + 0.5))

	# ------------------------------------------------------------- фасадные детали
	## Поясок/карниз по периметру на высоте y.
	func ring(mat: String, y: float, h: float, o: float) -> void:
		box(mat, Vector3(0, y, d * 0.5 + o * 0.5), Vector3(w + 2.0 * o, h, o))
		box(mat, Vector3(0, y, -d * 0.5 - o * 0.5), Vector3(w + 2.0 * o, h, o))
		box(mat, Vector3(w * 0.5 + o * 0.5, y, 0), Vector3(o, h, d))
		box(mat, Vector3(-w * 0.5 - o * 0.5, y, 0), Vector3(o, h, d))

	func belts() -> void:
		for fl in range(1, floors):
			ring(trim, yk(fl) - 0.06, 0.14, 0.05)

	## Водосточная труба у стены (x,z — ось трубы), сверху воронка, снизу колено наружу nrm.
	func downpipe(x: float, z: float, ytop: float, nrm: Vector3) -> void:
		cyl(sill, Vector3(x, (ytop - 0.1 + 0.42) * 0.5, z), 0.05, ytop - 0.1 - 0.42, 6, Basis(), -1.0, false)
		cyl(sill, Vector3(x, ytop, z), 0.055, 0.22, 6, Basis(), 0.13, false)
		tube(sill, Vector3(x, 0.44, z), Vector3(x, 0.2, z) + nrm * 0.22, 0.05)
		for k in 3:
			box("plate_dark", Vector3(x, 0.8 + (ytop - 1.0) * k * 0.45, z) - nrm * 0.05, Vector3(0.04, 0.03, 0.1), false,
				Basis(Vector3.UP, atan2(nrm.x, nrm.z)))

	## Кондиционер на стене стороны si в точке u (вдоль стены) на высоте y.
	func ac(si: int, u: float, y: float) -> void:
		var s := side(si)
		var a: Vector3 = s[0]
		var dir: Vector3 = s[1]
		var n: Vector3 = s[2]
		var bas := Basis(dir, Vector3.UP, n)
		var c := a + dir * u + Vector3(0, y, 0)
		var o := th * 0.5
		box("concrete", c + n * (o + 0.17), Vector3(0.8, 0.52, 0.28), false, bas)
		box("plate_dark", c + dir * 0.12 + n * (o + 0.315), Vector3(0.38, 0.38, 0.012), false, bas)
		for sd in [-1.0, 1.0]:
			box("plate_dark", c + dir * (sd * 0.3) + Vector3(0, -0.28, 0) + n * (o + 0.17), Vector3(0.04, 0.04, 0.34), false, bas)
		decal(c + dir * 0.25 + Vector3(0, -0.85, 0) + n * (o + 0.012), n, dir, Vector2(0.4, 1.1), 0)

	## Спутниковая тарелка в точке p, смотрит в сторону facing.
	func dish(p: Vector3, facing: Vector3) -> void:
		var ax := (facing.normalized() * 0.8 + Vector3.UP * 0.55).normalized()
		var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
		var x := ref.cross(ax).normalized()
		var z := x.cross(ax)
		var bas := Basis(x, ax, z)
		cyl("concrete", p, 0.04, 0.1, 8, bas, 0.33, true)
		bar("plate_dark", p, p + ax * 0.42 - Vector3(0, 0.1, 0), Vector2(0.025, 0.025))
		box("plate_dark", p + ax * 0.42 - Vector3(0, 0.1, 0), Vector3(0.06, 0.06, 0.08))
		bar("plate_dark", p - ax * 0.05, p - ax * 0.05 - facing.normalized() * 0.25, Vector2(0.04, 0.04))

	## Случайные пятна на стенах (мягкие разводы).
	func stains(count0: int, hmax := 2.6) -> void:
		var count := (count0 + 2) / 3
		for i in count:
			var si := rng.randi() % 4
			var s := side(si)
			var a: Vector3 = s[0]
			var dir: Vector3 = s[1]
			var n: Vector3 = s[2]
			var ln: float = s[3]
			var sz := Vector2(rng.randf_range(0.8, 2.2), rng.randf_range(0.8, 1.8))
			var u := rng.randf_range(sz.x * 0.5, maxf(sz.x * 0.5, ln - sz.x * 0.5))
			var y := floor_y + rng.randf_range(sz.y * 0.5, maxf(sz.y * 0.5, hmax - sz.y * 0.5))
			decal(a + dir * u + Vector3(0, y, 0) + n * (th * 0.5 + 0.011), n, dir, sz, 1)

	## Подтёки под карнизом/парапетом по всему периметру.
	func eave_streaks(y: float) -> void:
		for si in 4:
			var s := side(si)
			var a: Vector3 = s[0]
			var dir: Vector3 = s[1]
			var n: Vector3 = s[2]
			var ln: float = s[3]
			var k := maxi(1, int(ln / 2.6))
			for i in k:
				if rng.randf() < 0.6:
					continue
				var hh := rng.randf_range(0.7, 1.6)
				decal(a + dir * (ln * (i + 0.5) / k) + Vector3(0, y - hh * 0.5, 0) + n * (th * 0.5 + 0.01), n, dir,
					Vector2(ln / k * rng.randf_range(0.6, 1.0), hh), 0)

	# ------------------------------------------------------------- крыши
	## Плоская крыша: плита (по всей площади, кроме holes [x0,x1,z0,z1]), рубероид, отлив по парапету,
	## карниз, водостоки через парапет, надстройки.
	func roof_flat(stuff := true, holes: Array = []) -> void:
		var y := top_y()
		var ix0 := -w * 0.5 + th
		var ix1 := w * 0.5 - th
		var iz0 := -d * 0.5 + th
		var iz1 := d * 0.5 - th
		if holes.is_empty():
			floor_rect(y, ix0, ix1, iz0, iz1, "asphalt")
		else:
			var hl: Array = holes[0]
			floor_hole(y, ix0, ix1, iz0, iz1, hl[0], hl[1], hl[2], hl[3], "asphalt")
		var py := y + parapet
		box(sill, Vector3(0, py + 0.02, d * 0.5 - th * 0.5), Vector3(w + 0.08, 0.04, th + 0.1))
		box(sill, Vector3(0, py + 0.02, -d * 0.5 + th * 0.5), Vector3(w + 0.08, 0.04, th + 0.1))
		box(sill, Vector3(w * 0.5 - th * 0.5, py + 0.02, 0), Vector3(th + 0.1, 0.04, d - 2.0 * th))
		box(sill, Vector3(-w * 0.5 + th * 0.5, py + 0.02, 0), Vector3(th + 0.1, 0.04, d - 2.0 * th))
		ring(trim, y - 0.05, 0.24, 0.12)
		eave_streaks(py - 0.05)
		# водостоки с задней стороны (через парапет)
		for sx in [-1.0, 1.0]:
			var x: float = sx * (w * 0.5 - 0.35)
			box(sill, Vector3(x, y + 0.08, -d * 0.5 - 0.06), Vector3(0.14, 0.08, 0.3))
			downpipe(x, -d * 0.5 - 0.1, y - 0.05, Vector3.FORWARD)
		if stuff:
			roof_stuff(y, holes)
		for p in [Vector3(ix0 + 0.6, y, iz1 - 0.6), Vector3(ix1 - 0.6, y, iz0 + 0.6), Vector3(0, y, iz1 - 0.6)]:
			pt("roof", p)

	## Надстройки плоской крыши: вентшахты, трубы, антенна, баки для воды, кондиционер.
	func roof_stuff(y: float, holes: Array) -> void:
		var placed: Array = []
		var tries := 0
		var want := 2 + int(w * d / 40.0)
		while placed.size() < want and tries < 30:
			tries += 1
			var p := Vector3(rng.randf_range(-w * 0.5 + 1.2, w * 0.5 - 1.2), y, rng.randf_range(-d * 0.5 + 1.2, d * 0.5 - 1.2))
			var ok := true
			for q in placed:
				if (q as Vector3).distance_to(p) < 2.0:
					ok = false
			for hl in holes:
				if p.x > float(hl[0]) - 1.0 and p.x < float(hl[1]) + 1.0 and p.z > float(hl[2]) - 1.0 and p.z < float(hl[3]) + 1.0:
					ok = false
			if not ok:
				continue
			placed.append(p)
			match rng.randi() % 5:
				0:
					box("rust", p + Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 0.9), true)
					box("plate_dark", p + Vector3(0, 0.84, 0), Vector3(1.05, 0.06, 1.05))
				1:
					cyl("rust", p + Vector3(0, 0.6, 0), 0.12, 1.2, 8, Basis(), -1.0, false)
					cyl("rust", p + Vector3(0, 1.22, 0), 0.2, 0.05, 8)
				2:
					# мачта антенны с растяжками
					cyl("plate_dark", p + Vector3(0, 1.5, 0), 0.03, 3.0, 5, Basis(), -1.0, false)
					for k in 3:
						box("plate_dark", p + Vector3(0, 2.2 + k * 0.35, 0), Vector3(0.9 - k * 0.2, 0.02, 0.02), false, Basis(Vector3.UP, rng.randf() * 0.4))
					dish(p + Vector3(0.5, 0.45, 0.3), Vector3(0.3, 0, 1))
				3:
					# бак для воды на подставке (ближневосточная крыша)
					for sx in [-0.4, 0.4]:
						box("plate_dark", p + Vector3(sx, 0.3, 0), Vector3(0.06, 0.6, 1.0))
					cyl("plate_dark", p + Vector3(0, 0.95, 0), 0.5, 0.7, 10, Basis(Vector3.BACK, PI * 0.5), -1.0, true, true)
				_:
					box("concrete", p + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.5), true)
					box("plate_dark", p + Vector3(0, 0.3, 0.255), Vector3(0.42, 0.42, 0.012))

	## Двускатная крыша (конёк вдоль X). Возвращает высоту конька.
	func roof_gable(pitch: float, ov := 0.45, og := 0.35, gable_mat := "", ceiling := true) -> float:
		var ye := top_y()
		var tp := tan(pitch)
		var hs := d * 0.5
		var yr := ye + 0.08 + hs * tp
		var ey := ye + 0.08 - ov * tp
		if ceiling:
			solid("concrete", Vector3(0, ye - 0.1, 0), Vector3(w - 2.0 * th, 0.2, d - 2.0 * th))
		var ln := (hs + ov) / cos(pitch)
		for sd in [1.0, -1.0]:
			var bas := Basis(Vector3.RIGHT, sd * pitch)
			var nrm := bas.y
			var zc: float = sd * (hs + ov) * 0.5
			var yc := yr - (hs + ov) * 0.5 * tp
			solid(roof, Vector3(0, yc, zc) - nrm * 0.03, Vector3(w + 2.0 * og, 0.06, ln), bas)
			# лобовая доска и желоб
			box("wood_dark", Vector3(0, ey - 0.07, sd * (hs + ov)), Vector3(w + 2.0 * og, 0.16, 0.03))
			tube(sill, Vector3(-w * 0.5 - og + 0.05, ey - 0.1, sd * (hs + ov + 0.05)), Vector3(w * 0.5 + og - 0.05, ey - 0.1, sd * (hs + ov + 0.05)), 0.06, 6)
			for sx in [-1.0, 1.0]:
				bar("wood_dark", Vector3(sx * (w * 0.5 + og), ey - 0.02, sd * (hs + ov)), Vector3(sx * (w * 0.5 + og), yr + 0.02, 0), Vector2(0.18, 0.03))
		box(roof, Vector3(0, yr + 0.03, 0), Vector3(w + 2.0 * og + 0.02, 0.05, 0.32))
		# фронтоны и слуховые окна
		var gm := gable_mat if gable_mat != "" else wall
		for sx in [-1.0, 1.0]:
			var x: float = sx * (w * 0.5 - th * 0.5)
			slab(gm, [Vector3(x, ye, -d * 0.5), Vector3(x, ye, d * 0.5), Vector3(x, yr + 0.02, 0)], Vector3(sx, 0, 0), th, Vector3(0, 0, 1))
			var vy := ye + (yr - ye) * 0.4
			box("wood_dark", Vector3(sx * (w * 0.5 + 0.01), vy, 0), Vector3(0.04, 0.55, 0.6))
			box("glass", Vector3(sx * (w * 0.5 + 0.025), vy, 0), Vector3(0.02, 0.43, 0.48))
		# водостоки по углам фасада и зада
		for sd in [1.0, -1.0]:
			for sx in [-1.0, 1.0]:
				if rng.randf() < 0.6:
					var px: float = sx * (w * 0.5 - 0.3)
					var pz: float = sd * (d * 0.5 + 0.08)
					tube(sill, Vector3(px, ey - 0.12, sd * (hs + ov)), Vector3(px, ey - 0.45, pz), 0.045)
					downpipe(px, pz, ey - 0.45, Vector3(0, 0, sd))
		eave_streaks(ye)
		return yr

	## Вальмовая крыша (четыре ската). Требует w >= d. Возвращает высоту конька.
	func roof_hip(pitch: float, ov := 0.45) -> float:
		var ye := top_y()
		var tp := tan(pitch)
		var hd := d * 0.5 + ov
		var hw := w * 0.5 + ov
		var yr := ye + 0.08 + d * 0.5 * tp
		var ey := ye + 0.08 - ov * tp
		var rx := maxf(0.0, w * 0.5 - d * 0.5)
		solid("concrete", Vector3(0, ye - 0.1, 0), Vector3(w - 2.0 * th, 0.2, d - 2.0 * th))
		var r1 := Vector3(-rx, yr, 0)
		var r2 := Vector3(rx, yr, 0)
		var efl := Vector3(-hw, ey, hd)
		var efr := Vector3(hw, ey, hd)
		var ebr := Vector3(hw, ey, -hd)
		var ebl := Vector3(-hw, ey, -hd)
		var planes := [
			[[efl, efr, r2, r1] if rx > 0.01 else [efl, efr, r1], Vector3.RIGHT],
			[[ebr, ebl, r1, r2] if rx > 0.01 else [ebr, ebl, r1], Vector3.LEFT],
			[[ebl, efl, r1], Vector3.BACK],
			[[efr, ebr, r2], Vector3.FORWARD],
		]
		for pl in planes:
			var pts: Array = pl[0]
			var p0: Vector3 = pts[0]
			var p1: Vector3 = pts[1]
			var p2: Vector3 = pts[2]
			var nrm := (p1 - p0).cross(p2 - p0).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			slab(roof, pts, nrm, 0.06, pl[1])
		# коллизия — два основных ската
		var ln := hd / cos(pitch)
		for sd in [1.0, -1.0]:
			var bas := Basis(Vector3.RIGHT, sd * pitch)
			col(Mats.surf(roof), Vector3(0, yr - hd * 0.5 * tp, sd * hd * 0.5), Vector3(w, 0.08, ln), bas)
		# коньки и рёбра
		if rx > 0.01:
			bar(roof, r1 + Vector3(-0.05, 0.03, 0), r2 + Vector3(0.05, 0.03, 0), Vector2(0.05, 0.3))
		for pr in [[efl, r1], [ebl, r1], [efr, r2], [ebr, r2]]:
			var pa: Vector3 = pr[0]
			var pb: Vector3 = pr[1]
			bar(roof, pa + Vector3(0, 0.04, 0), pb + Vector3(0, 0.04, 0), Vector2(0.04, 0.22))
		# лобовые доски и желоба
		for sd in [1.0, -1.0]:
			box("wood_dark", Vector3(0, ey - 0.07, sd * hd), Vector3(2.0 * hw, 0.16, 0.03))
			box("wood_dark", Vector3(sd * hw, ey - 0.07, 0), Vector3(0.03, 0.16, 2.0 * hd))
			tube(sill, Vector3(-hw, ey - 0.1, sd * (hd + 0.05)), Vector3(hw, ey - 0.1, sd * (hd + 0.05)), 0.06, 6)
			for sx in [-1.0, 1.0]:
				if rng.randf() < 0.6:
					var px: float = sx * (w * 0.5 - 0.3)
					var pz: float = sd * (d * 0.5 + 0.08)
					tube(sill, Vector3(px, ey - 0.12, sd * hd), Vector3(px, ey - 0.45, pz), 0.045)
					downpipe(px, pz, ey - 0.45, Vector3(0, 0, sd))
		eave_streaks(ye)
		return yr

	## Высота ската двускатной/вальмовой крыши над точкой z (для труб).
	func roof_h(z: float, pitch: float) -> float:
		return top_y() + 0.08 + (d * 0.5 - absf(z)) * tan(pitch)

	## Печная/вентиляционная труба через крышу.
	func chimney(x: float, z: float, ytop: float) -> void:
		var y0 := top_y() - 0.2
		box("concrete", Vector3(x, (y0 + ytop) * 0.5, z), Vector3(0.52, ytop - y0, 0.52))
		box("concrete", Vector3(x, ytop + 0.04, z), Vector3(0.64, 0.08, 0.64))
		box("plate_dark", Vector3(x, ytop + 0.28, z), Vector3(0.6, 0.04, 0.6))
		for sx in [-0.24, 0.24]:
			box("plate_dark", Vector3(x + sx, ytop + 0.16, z), Vector3(0.03, 0.22, 0.03))
		decal(Vector3(x, ytop - 0.6, z + 0.265), Vector3.BACK, Vector3.RIGHT, Vector2(0.5, 1.0), 0)

	# ------------------------------------------------------------- интерьер
	## Перегородка от p0 до p1 (x,z) на этаже fl с дверями [t0, t1] вдоль неё.
	func partition(p0: Vector2, p1: Vector2, fl: int, doors: Array, thick := 0.12, mat := "", h := -1.0) -> void:
		var y := yk(fl)
		var hh := h if h > 0.0 else fh - 0.2
		var cut: Array = []
		for dr in doors:
			cut.append([dr[0], dr[1], 0.0, DOOR_H - 0.05])
		var a := Vector3(p0.x, y, p0.y)
		var b2 := Vector3(p1.x, y, p1.y)
		wall_ab(mat if mat != "" else inner, a, b2, hh, thick, cut)
		var dir := (b2 - a).normalized()
		var n := dir.cross(Vector3.UP)
		for dr in doors:
			door_at(Vector3(p0.x, 0, p0.y), dir, n, thick, dr[0], dr[1], y, y + DOOR_H - 0.05, "wood_dark", false, true)

	func fbox(mat: String, p: Vector3, bas: Basis, c: Vector3, s: Vector3) -> void:
		box(mat, p + bas * c, s, false, bas)

	## Мебель: p — точка на полу, yaw_l — поворот (лицом в +Z при 0).
	func furn(kind: String, p: Vector3, yaw_l := 0.0) -> void:
		var bas := Basis(Vector3.UP, yaw_l)
		match kind:
			"table":
				fbox("wood_dark", p, bas, Vector3(0, 0.74, 0), Vector3(1.2, 0.05, 0.7))
				for sx in [-0.54, 0.54]:
					for sz in [-0.29, 0.29]:
						fbox("wood_dark", p, bas, Vector3(sx, 0.36, sz), Vector3(0.05, 0.72, 0.05))
				col("wood", p + Vector3(0, 0.38, 0), Vector3(1.2, 0.76, 0.7), bas)
			"desk":
				fbox("wood_dark", p, bas, Vector3(0, 0.74, 0), Vector3(1.4, 0.05, 0.7))
				fbox("wood_dark", p, bas, Vector3(0.45, 0.36, 0), Vector3(0.45, 0.72, 0.65))
				fbox("wood_dark", p, bas, Vector3(-0.66, 0.36, 0), Vector3(0.04, 0.72, 0.65))
				fbox("plate_dark", p, bas, Vector3(-0.2, 0.9, -0.15), Vector3(0.45, 0.28, 0.04))
				col("wood", p + Vector3(0, 0.38, 0), Vector3(1.4, 0.76, 0.7), bas)
			"chair":
				fbox("wood_dark", p, bas, Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.42))
				fbox("wood_dark", p, bas, Vector3(0, 0.72, -0.19), Vector3(0.42, 0.5, 0.04))
				fbox("wood_dark", p, bas, Vector3(0, 0.22, -0.17), Vector3(0.38, 0.44, 0.04))
			"wardrobe":
				fbox("wood_dark", p, bas, Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 0.55))
				fbox("wood_dark", p, bas, Vector3(0, 2.03, 0.02), Vector3(1.06, 0.06, 0.6))
				fbox("plate_dark", p, bas, Vector3(0, 1.0, 0.28), Vector3(0.012, 1.85, 0.012))
				col("wood", p + Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 0.55), bas)
			"bed":
				fbox("wood_dark", p, bas, Vector3(0, 0.22, 0), Vector3(0.95, 0.24, 2.0))
				fbox("canvas", p, bas, Vector3(0, 0.41, 0.02), Vector3(0.9, 0.14, 1.92))
				fbox("concrete", p, bas, Vector3(0, 0.52, -0.72), Vector3(0.6, 0.1, 0.36))
				fbox("wood_dark", p, bas, Vector3(0, 0.45, -1.0), Vector3(0.95, 0.8, 0.05))
				col("wood", p + Vector3(0, 0.25, 0), Vector3(0.95, 0.5, 2.0), bas)
			"shelf":
				for sx in [-0.5, 0.5]:
					fbox("wood_dark", p, bas, Vector3(sx, 0.9, 0), Vector3(0.03, 1.8, 0.4))
				for k in 4:
					fbox("wood_dark", p, bas, Vector3(0, 0.1 + k * 0.55, 0), Vector3(1.0, 0.03, 0.4))
					if k < 3 and rng.randf() < 0.8:
						var s := rng.randf_range(0.2, 0.35)
						fbox("wood" if rng.randf() < 0.6 else "canvas", p, bas, Vector3(rng.randf_range(-0.3, 0.3), 0.115 + k * 0.55 + s * 0.5, 0), Vector3(s * 1.3, s, s))
				col("wood", p + Vector3(0, 0.9, 0), Vector3(1.0, 1.8, 0.4), bas)
			"stove":
				fbox("concrete", p, bas, Vector3(0, 0.95, 0), Vector3(1.25, 1.9, 1.1))
				fbox("concrete", p, bas, Vector3(0, 1.93, 0), Vector3(1.35, 0.08, 1.2))
				fbox("plate_dark", p, bas, Vector3(0.2, 0.55, 0.553), Vector3(0.45, 0.32, 0.012))
				col("concrete", p + Vector3(0, 0.95, 0), Vector3(1.25, 1.9, 1.1), bas)
			"counter":
				fbox("wood_dark", p, bas, Vector3(0, 0.5, 0), Vector3(2.4, 1.0, 0.6))
				fbox("concrete", p, bas, Vector3(0, 1.02, 0.03), Vector3(2.5, 0.04, 0.72))
				fbox("glass", p, bas, Vector3(0, 0.62, 0.305), Vector3(2.2, 0.5, 0.012))
				col("wood", p + Vector3(0, 0.52, 0), Vector3(2.4, 1.04, 0.66), bas)
			"cabinet":
				fbox("green", p, bas, Vector3(0, 0.65, 0), Vector3(0.5, 1.3, 0.6))
				for k in 3:
					fbox("plate_dark", p, bas, Vector3(0, 0.25 + k * 0.4, 0.305), Vector3(0.14, 0.03, 0.02))
				col("metal", p + Vector3(0, 0.65, 0), Vector3(0.5, 1.3, 0.6), bas)
			"crate":
				var s := rng.randf_range(0.6, 1.0)
				fbox("wood", p, bas, Vector3(0, s * 0.5, 0), Vector3(s, s, s))
				for sy in [-1.0, 1.0]:
					fbox("wood_dark", p, bas, Vector3(0, s * 0.5 + sy * (s * 0.5 - 0.04), 0), Vector3(s + 0.03, 0.08, s + 0.03))
				col("wood", p + Vector3(0, s * 0.5, 0), Vector3(s, s, s), bas)
			"pallet":
				fbox("wood_dark", p, bas, Vector3(0, 0.07, 0), Vector3(1.2, 0.14, 1.0))
				if rng.randf() < 0.7:
					var hh := rng.randf_range(0.5, 1.1)
					fbox("canvas" if rng.randf() < 0.5 else "wood", p, bas, Vector3(0, 0.14 + hh * 0.5, 0), Vector3(1.1, hh, 0.9))
					col("wood", p + Vector3(0, (0.14 + hh) * 0.5, 0), Vector3(1.2, 0.14 + hh, 1.0), bas)
			"barrel":
				cyl(_pick_l(["rust", "green", "container_blue"]), p + Vector3(0, 0.45, 0), 0.3, 0.9, 10, Basis(), -1.0, true, true)
			"tire":
				cyl("plate_dark", p + Vector3(0, 0.12, 0), 0.36, 0.24, 10, Basis(), -1.0, true)
			"bench":
				fbox("wood", p, bas, Vector3(0, 0.45, 0), Vector3(1.6, 0.05, 0.4))
				fbox("wood", p, bas, Vector3(0, 0.75, -0.2), Vector3(1.6, 0.18, 0.04))
				for sx in [-0.65, 0.65]:
					fbox("concrete", p, bas, Vector3(sx, 0.22, 0), Vector3(0.1, 0.44, 0.4))
			"firewood":
				fbox("wood_dark", p, bas, Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 0.45))
				fbox("iron", p, bas, Vector3(0, 1.08, 0), Vector3(2.0, 0.03, 0.6))
				col("wood", p + Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 0.45), bas)
			"rack":
				for sx in [-1.3, 1.3]:
					for sz in [-0.5, 0.5]:
						fbox("plate_dark", p, bas, Vector3(sx, 1.5, sz), Vector3(0.08, 3.0, 0.08))
				for k in 3:
					var yy := 0.15 + k * 1.0
					for sz in [-0.5, 0.5]:
						fbox("roof_red", p, bas, Vector3(0, yy, sz), Vector3(2.68, 0.1, 0.06))
					fbox("wood_dark", p, bas, Vector3(0, yy + 0.065, 0), Vector3(2.6, 0.03, 1.0))
					for j in rng.randi_range(0, 2):
						var s := rng.randf_range(0.45, 0.8)
						fbox("wood" if rng.randf() < 0.6 else "canvas", p, bas, Vector3(rng.randf_range(-0.8, 0.8), yy + 0.08 + s * 0.5, 0), Vector3(s * 1.2, s, s))
				col("metal", p + Vector3(0, 1.5, 0), Vector3(2.7, 3.0, 1.1), bas)
			"sofa":
				fbox("canvas", p, bas, Vector3(0, 0.22, 0), Vector3(1.8, 0.44, 0.8))
				fbox("canvas", p, bas, Vector3(0, 0.6, -0.32), Vector3(1.8, 0.4, 0.16))
				for sx in [-0.85, 0.85]:
					fbox("canvas", p, bas, Vector3(sx, 0.32, 0), Vector3(0.14, 0.64, 0.8))
				col("wood", p + Vector3(0, 0.4, 0), Vector3(1.8, 0.8, 0.8), bas)

	func _pick_l(arr: Array) -> String:
		return String(arr[rng.randi() % arr.size()])

	## Перила вдоль марша: от низа p0 до верха p1 (уровни ступеней), высота 0.9.
	func handrail(p0: Vector3, p1: Vector3, mat := "plate_dark") -> void:
		bar(mat, p0 + Vector3(0, 0.92, 0), p1 + Vector3(0, 0.92, 0), Vector2(0.05, 0.05))
		for k in 3:
			var p := p0.lerp(p1, (k + 0.5) / 3.0)
			box(mat, p + Vector3(0, 0.46, 0), Vector3(0.03, 0.92, 0.03))

	## Подшивка под маршем (видимая снизу косоур-плита), без коллизии.
	func stair_soffit(base: Vector3, yaw_l: float, width: float, rise: float, run: float, mat := "concrete") -> void:
		var rot := Basis(Vector3.UP, yaw_l)
		var ang := atan2(rise, run)
		var ln := sqrt(rise * rise + run * run)
		var rb := rot * Basis(Vector3.RIGHT, ang)
		var c := base + rot * Vector3(0, rise * 0.5, -run * 0.5) - rb * Vector3(0, 0.2, 0)
		box(mat, c, Vector3(width, 0.16, ln), false, rb)

	## Прямоугольный двор с глухим забором (доски или профлист) и калиткой в стороне +Z.
	func fence_rect(x0: float, x1: float, z0: float, z1: float, gate_x: float, mat: String, h: float) -> void:
		var corners := [Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Vector2(x0, z0)]
		for i in 4:
			var pa: Vector2 = corners[i]
			var pb: Vector2 = corners[(i + 1) % 4]
			var segs: Array = []
			if i == 0:
				segs = [[pa, Vector2(gate_x - 0.7, pa.y)], [Vector2(gate_x + 0.7, pa.y), pb]]
			else:
				segs = [[pa, pb]]
			for sg in segs:
				var s0: Vector2 = sg[0]
				var s1: Vector2 = sg[1]
				var ln := s0.distance_to(s1)
				if ln < 0.2:
					continue
				var n := maxi(1, int(ceil(ln / 2.5)))
				var dv := (s1 - s0) / ln
				var fy := atan2(-dv.y, dv.x)
				for k in n:
					var q0 := s0 + dv * (ln * k / n)
					var q1 := s0 + dv * (ln * (k + 1) / n)
					var m := (q0 + q1) * 0.5
					box("wood_dark" if mat == "wood" else "plate_dark", Vector3(q0.x, h * 0.5 + 0.1, q0.y), Vector3(0.08, h + 0.2, 0.08), true)
					if rng.randf() < 0.08:
						continue
					var bas := Basis(Vector3.UP, fy)
					if rng.randf() < 0.07:
						box(mat, Vector3(m.x, h * 0.45, m.y), Vector3(ln / n - 0.04, h, 0.03), false, bas * Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15)) * Basis(Vector3.RIGHT, rng.randf_range(0.15, 0.3)))
						continue
					box(mat, Vector3(m.x, h * 0.5 + 0.05, m.y), Vector3(ln / n - 0.02, h, 0.03), true, bas)
					for ry in [0.35, h - 0.25]:
						box("wood_dark" if mat == "wood" else "plate_dark", Vector3(m.x, ry, m.y) - Vector3(dv.y, 0, -dv.x) * 0.04, Vector3(ln / n, 0.06, 0.04), false, bas)
				box("wood_dark" if mat == "wood" else "plate_dark", Vector3(s1.x, h * 0.5 + 0.1, s1.y), Vector3(0.08, h + 0.2, 0.08), true)
		# калитка открыта наружу
		var hinge := Vector3(gate_x - 0.66, 0, z1)
		var lb := Basis(Vector3.UP, -rng.randf_range(0.9, 1.5))
		box(mat, hinge + lb * Vector3(0.62, h * 0.48 + 0.08, 0.03), Vector3(1.24, h - 0.1, 0.03), false, lb)
		pt("doors", Vector3(gate_x, 0, z1 + 1.0))
		pt("cover", Vector3(gate_x - 1.6, 0, z1 - 0.6))
		pt("cover", Vector3(gate_x + 1.6, 0, z1 - 0.6))

	## Обломки: груда коробок в эллипсе rx x rz вокруг p (на высоте p.y).
	func rubble(p: Vector3, rx: float, rz: float, count: int, mats: Array, collide_h := 0.0) -> void:
		for i in count:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf())
			var q := p + Vector3(cos(a) * rx * r, 0, sin(a) * rz * r)
			var s := Vector3(rng.randf_range(0.15, 0.7), rng.randf_range(0.1, 0.4), rng.randf_range(0.15, 0.6)) * (1.2 - r * 0.6)
			var bas := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
			box(_pick_l(mats), q + Vector3(0, s.y * 0.3 + (1.0 - r) * 0.25, 0), s, false, bas)
		if collide_h > 0.0:
			col("concrete", p + Vector3(0, collide_h * 0.5, 0), Vector3(rx * 1.2, collide_h, rz * 1.2))

	## Углы здания — укрытия снаружи; центр — точка внутри.
	func corner_points() -> void:
		for c in [Vector3(-w * 0.5 - 0.7, 0, -d * 0.5 - 0.7), Vector3(w * 0.5 + 0.7, 0, -d * 0.5 - 0.7),
				Vector3(-w * 0.5 - 0.7, 0, d * 0.5 + 0.7), Vector3(w * 0.5 + 0.7, 0, d * 0.5 + 0.7)]:
			pt("cover", c)

	func info() -> Dictionary:
		return {"pos": xf.origin, "yaw": yaw, "w": w, "d": d, "floor_y": xf.origin.y + floor_y, "top_y": xf.origin.y + top_y()}


# =====================================================================================
#                                    ТИПЫ ЗДАНИЙ
# =====================================================================================

## Частный дом в 1 этаж: три комнаты, печь с трубой, двускатная или вальмовая крыша, ставни/наличники,
## крыльцо с навесом. opt: fence (bool) — двор с забором и калиткой, east (bool) — плоская крыша с парапетом.
static func house(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	var east: bool = opt.get("east", false)
	b.w = snappedf(rng.randf_range(8.4, 10.4), 0.1)
	b.d = snappedf(rng.randf_range(6.6, 7.6), 0.1)
	b.fh = 2.9
	b.floor_y = rng.randf_range(0.35, 0.55)
	b.wall = _pick(rng, walls_east if east else walls_house)
	b.roof = _pick(rng, roofs)
	b.floor_mat = "wood"
	b.frame = "wood_dark" if rng.randf() < 0.4 else "concrete"
	b.nalich = "" if east else ["", "wood_dark", "concrete", "wood"][rng.randi() % 4]
	b.shutters = not east and rng.randf() < 0.45
	b.shut = _pick(rng, ["wood_dark", "green", "wood"])
	b.grilles = east or rng.randf() < 0.25
	b.canopy = 2 if rng.randf() < 0.6 else 3
	b.parapet = 0.6 if east else 0.0
	var ix0 := -b.w * 0.5 + b.th
	var ix1 := b.w * 0.5 - b.th
	var iz0 := -b.d * 0.5 + b.th
	var iz1 := b.d * 0.5 - b.th
	var px := ix0 + (ix1 - ix0) * rng.randf_range(0.42, 0.5)
	var pz := iz1 - 2.8
	# проёмы
	var dx := ix0 + 0.3
	b.op_at(0, 0, dx, dx + DOOR_W, 0.0, DOOR_H, "door")
	if px - (dx + DOOR_W) > 2.0:
		b.spread(0, 0, dx + DOOR_W + 0.2, px, 1, 1.1)
	b.spread(0, 0, px, ix1, 2 if ix1 - px > 3.8 else 1, 1.3)
	b.spread(0, 1, iz0, iz1, 2 if b.d > 7.1 else 1, 1.3)
	b.spread(0, 2, px, ix1, 1, 1.3)
	b.spread(0, 2, ix0, px, 1, 1.1)
	b.spread(0, 3, pz, iz1, 1, 1.1)
	b.spread(0, 3, iz0, pz, 1, 1.1)
	b.base_slab()
	b.walls()
	# перегородки
	b.partition(Vector2(px, iz1), Vector2(px, iz0), 0, [[0.25, 0.25 + IDOOR_W]])
	b.partition(Vector2(ix0, pz), Vector2(px - 0.06, pz), 0, [[0.25, 0.25 + IDOOR_W]])
	# печь и мебель
	var y := b.floor_y
	b.furn("stove", Vector3(px - 0.74, y, pz + 0.68), -PI * 0.5)
	b.furn("bed", Vector3(ix0 + 0.55, y, iz0 + 1.05))
	b.furn("wardrobe", Vector3(px - 0.62, y, iz0 + 0.34))
	b.furn("bed", Vector3(ix1 - 0.55, y, iz0 + 1.05))
	b.furn("wardrobe", Vector3(px + 0.4, y, iz0 + 0.62), PI * 0.5)
	b.furn("table", Vector3((px + ix1) * 0.5, y, 0.6))
	b.furn("chair", Vector3((px + ix1) * 0.5 - 0.3, y, 1.2), PI)
	b.furn("shelf", Vector3(px + 0.26, y, -1.0), PI * 0.5)
	# крыша
	var pitch := rng.randf_range(0.42, 0.58)
	if east:
		b.roof_flat(true)
		b.dish(Vector3(ix1 - 0.6, b.top_y() + 0.9, iz1 - 0.3), Vector3(0.2, 0, 1))
	elif rng.randf() < 0.55:
		var yr := b.roof_gable(pitch, 0.45, 0.35, "wood" if rng.randf() < 0.4 else "")
		b.chimney(px - 0.74, pz + 0.68, maxf(b.roof_h(pz + 0.68, pitch), yr - 0.3) + 0.55)
	else:
		var yr2 := b.roof_hip(pitch)
		b.chimney(px - 0.74, pz + 0.68, maxf(b.roof_h(pz + 0.68, pitch), yr2 - 0.3) + 0.55)
	if rng.randf() < 0.5:
		b.ac(1, 1.4, b.floor_y + 2.0)
	if rng.randf() < 0.4:
		b.dish(Vector3(b.w * 0.5 + 0.1, b.floor_y + 2.6, b.d * 0.5 - 0.6), Vector3(1, 0, 0.6))
	b.stains(rng.randi_range(2, 5))
	b.pt("inside", Vector3((ix0 + px) * 0.5, y, (pz + iz1) * 0.5))
	b.pt("inside", Vector3((px + ix1) * 0.5, y, -0.5))
	b.corner_points()
	if opt.get("fence", false):
		var mx := rng.randf_range(3.0, 5.0)
		var fz1 := b.d * 0.5 + rng.randf_range(3.5, 6.0)
		b.fence_rect(-b.w * 0.5 - mx, b.w * 0.5 + rng.randf_range(2.0, 4.0), -b.d * 0.5 - rng.randf_range(2.5, 6.0), fz1,
			dx + DOOR_W * 0.5, "wood" if rng.randf() < 0.5 else "iron", rng.randf_range(1.5, 1.9))
		if rng.randf() < 0.6:
			b.furn("firewood", Vector3(b.w * 0.5 + 1.0, 0, -b.d * 0.5 + 1.2), -PI * 0.5)
		if rng.randf() < 0.5:
			b.furn("bench", Vector3(dx - 1.3, 0, b.d * 0.5 + 0.45), 0.0)
	return b.info()


## Дом в 2 этажа: прихожая с лестницей у левой стены, по две комнаты на этаже, балкон (не всегда),
## крыша двускатная/вальмовая или плоская с парапетом (ближневосточный вариант, opt.east).
static func house2(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	var east: bool = opt.get("east", rng.randf() < 0.35)
	b.w = snappedf(rng.randf_range(9.4, 11.0), 0.1)
	b.d = snappedf(rng.randf_range(8.2, 9.0), 0.1)
	b.fh = 3.0
	b.floors = 2
	b.floor_y = rng.randf_range(0.35, 0.5)
	b.wall = _pick(rng, walls_east if east else walls_house)
	b.roof = _pick(rng, roofs)
	b.frame = "concrete" if rng.randf() < 0.65 else "wood_dark"
	b.nalich = "" if east or rng.randf() < 0.5 else _pick(rng, ["wood_dark", "concrete"])
	b.grilles = rng.randf() < 0.5
	b.shutters = not east and rng.randf() < 0.3
	b.shut = _pick(rng, ["wood_dark", "green"])
	b.canopy = 1 if rng.randf() < 0.5 else 3
	b.parapet = 0.7 if east else 0.0
	b.floor_mat = "wood" if rng.randf() < 0.5 else "concrete"
	var ix0 := -b.w * 0.5 + b.th
	var ix1 := b.w * 0.5 - b.th
	var iz0 := -b.d * 0.5 + b.th
	var iz1 := b.d * 0.5 - b.th
	var hx := ix0 + 2.5
	var pz := rng.randf_range(-0.4, 0.4)
	var zs := iz1 - 1.25
	var run := 4.2
	# проёмы
	b.op_at(0, 0, ix0 + 1.2, ix0 + 1.2 + DOOR_W, 0.0, DOOR_H, "door")
	b.op_at(1, 0, ix0 + 0.6, ix0 + 1.9, 0.85, 2.2, "win")
	var balcony := rng.randf() < 0.55
	for fl in 2:
		if fl == 1 and balcony:
			var bx := ix1 - 1.0 - 1.1
			b.op_at(1, 0, bx, bx + 1.1, 0.0, DOOR_H, "bdoor")
			b.spread(1, 0, hx + 0.2, bx - 0.3, 1, 1.3)
		else:
			b.spread(fl, 0, hx + 0.2, ix1, 2 if ix1 - hx > 4.2 else 1, 1.35)
		b.spread(fl, 2, hx, ix1, 2 if ix1 - hx > 4.2 else 1, 1.35)
		b.spread(fl, 1, pz, iz1, 1, 1.3)
		b.spread(fl, 1, iz0, pz, 1, 1.3)
		b.spread(fl, 3, iz0, iz0 + 2.4, 1, 1.0)
	b.base_slab()
	b.walls()
	b.belts()
	# лестница вдоль левой стены, вверх к задней стене
	var y0 := b.floor_y
	var sx := ix0 + 0.6
	b.stairs("wood_dark" if b.floor_mat == "wood" else "concrete", Vector3(sx, y0, zs), 0.0, 1.1, b.fh, run)
	b.stair_soffit(Vector3(sx, y0, zs), 0.0, 1.1, b.fh, run, "wood_dark" if b.floor_mat == "wood" else "concrete")
	b.handrail(Vector3(sx + 0.58, y0, zs), Vector3(sx + 0.58, y0 + b.fh, zs - run), "wood_dark")
	var y1 := b.yk(1)
	b.floor_hole(y1, ix0, ix1, iz0, iz1, ix0, ix0 + 1.2, zs - run, zs - 1.0)
	# ограждение проёма наверху
	b.box("wood_dark", Vector3(ix0 + 1.23, y1 + 0.5, zs - run * 0.5 - 0.5), Vector3(0.05, 1.0, run - 1.0), true)
	b.box("wood_dark", Vector3(ix0 + 0.6, y1 + 0.5, zs - 1.0 + 0.03), Vector3(1.2, 1.0, 0.05), true)
	# перегородки обоих этажей
	for fl in 2:
		b.partition(Vector2(hx, iz1), Vector2(hx, iz0), fl, [[iz1 - pz - 2.3, iz1 - pz - 2.3 + IDOOR_W], [iz1 - pz + 0.6, iz1 - pz + 0.6 + IDOOR_W]])
		b.partition(Vector2(hx + 0.06, pz), Vector2(ix1, pz), fl, [])
		var y := b.yk(fl)
		b.furn("bed" if fl == 1 else "sofa", Vector3(ix1 - 0.55 if fl == 1 else ix1 - 1.0, y, iz0 + 1.05 if fl == 1 else iz0 + 0.42), 0.0)
		b.furn("wardrobe", Vector3(ix1 - 0.33, y, pz - 0.65), -PI * 0.5)
		b.furn("table", Vector3((hx + ix1) * 0.5, y, (pz + iz1) * 0.5 + 0.2))
		b.furn("chair", Vector3((hx + ix1) * 0.5 + 0.2, y, (pz + iz1) * 0.5 - 0.45))
		b.furn("shelf", Vector3(ix1 - 0.25, y, pz + 0.6), -PI * 0.5)
		b.pt("inside", Vector3((hx + ix1) * 0.5, y, (pz + iz1) * 0.5))
		b.pt("inside", Vector3((hx + ix1) * 0.5, y, (pz + iz0) * 0.5))
	if balcony:
		_balcony(b, 1, 0, b.tof(0, ix1 - 2.1) - 0.8, b.tof(0, ix1 - 1.0) + 0.7)
	# крыша
	var pitch := rng.randf_range(0.4, 0.52)
	if east:
		b.roof_flat(true)
	elif rng.randf() < 0.5:
		b.roof_gable(pitch, 0.5, 0.4)
	else:
		b.roof_hip(pitch, 0.5)
	for k in rng.randi_range(0, 2):
		b.ac(rng.randi_range(1, 3) if k == 0 else 2, rng.randf_range(1.5, 3.5), b.yk(rng.randi_range(0, 1)) + 2.0)
	if rng.randf() < 0.5:
		b.dish(Vector3(-b.w * 0.5 - 0.1, b.yk(1) + 2.2, b.d * 0.5 - 1.0), Vector3(-1, 0, 0.5))
	b.stains(rng.randi_range(3, 6), 5.5)
	b.corner_points()
	return b.info()


## Балкон на этаже fl стороны si от u0 до u1 (вдоль стены): плита, ограждение с коллизией, иногда остеклён.
static func _balcony(b: B, fl: int, si: int, u0: float, u1: float) -> void:
	var s := b.side(si)
	var a: Vector3 = s[0]
	var dir: Vector3 = s[1]
	var n: Vector3 = s[2]
	var bas := Basis(dir, Vector3.UP, n)
	var y := b.yk(fl)
	var ln := u1 - u0
	var c := a + dir * ((u0 + u1) * 0.5) + Vector3(0, y, 0)
	var o := b.th * 0.5
	var dp := 1.1
	b.solid("concrete", c + Vector3(0, -0.09, 0) + n * (o + dp * 0.5), Vector3(ln, 0.18, dp), bas)
	b.box("wood" if b.floor_mat == "wood" else "concrete", c + Vector3(0, 0.005, 0) + n * (o + dp * 0.5), Vector3(ln - 0.1, 0.01, dp - 0.06), false, bas)
	var rm := b.rail
	b.solid(rm, c + Vector3(0, 0.52, 0) + n * (o + dp - 0.03), Vector3(ln, 0.95, 0.05), bas)
	for sd in [-1.0, 1.0]:
		b.solid(rm, c + dir * (sd * (ln * 0.5 - 0.03)) + Vector3(0, 0.52, 0) + n * (o + dp * 0.5), Vector3(0.05, 0.95, dp - 0.06), bas)
	b.box("plate_dark", c + Vector3(0, 1.02, 0) + n * (o + dp - 0.03), Vector3(ln + 0.04, 0.05, 0.08), false, bas)
	if b.rng.randf() < 0.35:
		# остеклённый балкон
		for k in 4:
			var u := -ln * 0.5 + 0.04 + (ln - 0.08) * k / 3.0
			b.box(b.frame, c + dir * u + Vector3(0, 1.75, 0) + n * (o + dp - 0.03), Vector3(0.06, 1.5, 0.06), false, bas)
		b.box(b.frame, c + Vector3(0, 2.5, 0) + n * (o + dp - 0.03), Vector3(ln, 0.08, 0.08), false, bas)
		b.box("glass", c + Vector3(0, 1.75, 0) + n * (o + dp - 0.02), Vector3(ln - 0.1, 1.42, 0.012), false, bas)
		b.box(b.roof if fl == b.floors - 1 else "iron", c + Vector3(0, 2.6, 0) + n * (o + dp * 0.5), Vector3(ln + 0.1, 0.04, dp + 0.1), false, bas)
	elif b.rng.randf() < 0.35:
		# бельё на перилах
		b.box("canvas", c + dir * b.rng.randf_range(-0.4, 0.4) + Vector3(0, 0.8, 0) + n * (o + dp + 0.01), Vector3(0.7, 0.55, 0.02), false, bas)
	b.pt("fire", c + n * (o + 0.5))


## Многоэтажка 3–4 этажа (одна секция, подъезд по центру): лестничная клетка с маршами и площадками,
## по две квартиры на этаже, балконы на фасаде, выход на крышу через будку. opt.floors — число этажей.
static func block(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	b.floors = int(opt.get("floors", 3 if rng.randf() < 0.65 else 4))
	b.w = snappedf(rng.randf_range(15.0, 17.0), 0.2)
	b.d = 10.0
	b.fh = 3.0
	b.floor_y = 0.45
	b.parapet = 0.6
	b.wall = _pick(rng, walls_block)
	b.trim = "concrete"
	b.frame = "concrete"
	b.leaf = _pick(rng, ["green", "plate_dark"])
	b.inner = "concrete"
	b.rail = _pick(rng, ["iron", "concrete", "rust"])
	b.grilles = rng.randf() < 0.6
	b.brow = 0.0
	b.canopy = 1
	b.broken = 0.2
	var ix0 := -b.w * 0.5 + b.th
	var ix1 := b.w * 0.5 - b.th
	var iz0 := -b.d * 0.5 + b.th
	var iz1 := b.d * 0.5 - b.th
	var zf := iz1 - 1.6          # граница передней площадки
	var run := 2.24              # марш на полэтажа: 8 ступеней по 0.28
	var zm := zf - run           # граница промежуточной площадки
	var zp := rng.randf_range(-0.2, 0.5)
	var nf := b.floors
	# проёмы фасада: подъезд, окна лестницы, по квартире слева и справа
	b.op_at(0, 0, -0.65, 0.65, 0.0, DOOR_H, "door")
	var balc: Array = []
	for fl in nf:
		if fl > 0 and fl < nf - 1:
			b.op_at(fl, 0, -0.6, 0.6, 0.9, 2.1, "win")
		for sx in [-1.0, 1.0]:
			var e0: float = sx * (b.w * 0.5 - b.th)
			var e1: float = sx * 1.6
			if fl > 0 and rng.randf() < 0.75:
				var bd0: float = e0 - sx * 0.8
				var bd1: float = bd0 - sx * 1.1
				b.op_at(fl, 0, bd0, bd1, 0.0, DOOR_H, "bdoor")
				b.spread(fl, 0, bd1 - sx * 0.3, e1, 1, 1.4)
				balc.append([fl, b.tof(0, bd0) + (0.75 if sx > 0 else -0.75), b.tof(0, bd1) - (0.75 if sx > 0 else -0.75)])
			else:
				b.spread(fl, 0, e0, e1, 2, 1.4)
			b.spread(fl, 2, e0, e1, 1, 1.4)
		b.spread(fl, 1, zp, iz1, 1, 1.3)
		b.spread(fl, 1, iz0, zp, 1, 1.3)
		b.spread(fl, 3, zp, iz1, 1, 1.3)
		b.spread(fl, 3, iz0, zp, 1, 1.3)
	# парапет над будкой выхода на крышу вырезаем — там стены будки
	b.add_op(nf - 1, 0, [b.w * 0.5 - 1.6, b.w * 0.5 + 1.6, b.fh, b.fh + b.parapet, "none"])
	b.add_op(nf - 1, 2, [b.w * 0.5 - 1.6, b.w * 0.5 + 1.6, b.fh, b.fh + b.parapet, "none"])
	b.base_slab()
	b.walls()
	b.belts()
	for bl in balc:
		var u0: float = minf(bl[1], bl[2])
		var u1: float = maxf(bl[1], bl[2])
		_balcony(b, bl[0], 0, u0, u1)
	# лестничная клетка: стены x = ±1.5 с дверями в квартиры, марши и площадки
	for fl in nf + 1:
		var y := b.yk(fl)
		var top := fl == nf
		for sx in [-1.0, 1.0]:
			var xw: float = sx * 1.5
			b.wall_ab(b.wall if top else b.inner, Vector3(xw, y, iz1), Vector3(xw, y, iz0), 2.8 if top else b.fh - 0.2, 0.2,
				[[0.2, 0.2 + IDOOR_W, 0.0, DOOR_H - 0.05]])
			b.door_at(Vector3(xw, 0, iz1), Vector3.FORWARD, Vector3(sx, 0, 0), 0.2, 0.2, 0.2 + IDOOR_W, y, y + DOOR_H - 0.05,
				b.leaf if not top else "plate_dark", false, true)
		if fl > 0:
			b.floor_rect(y, -1.4, 1.4, zf, iz1, "concrete")
		if fl < nf:
			# марш вверх (левая половина), площадка, марш обратно (правая половина)
			b.stairs("concrete", Vector3(-0.72, y, zf), 0.0, 1.2, 1.5, run)
			b.stair_soffit(Vector3(-0.72, y, zf), 0.0, 1.2, 1.5, run)
			b.floor_rect(y + 1.5, -1.4, 1.4, iz0, zm, "concrete")
			b.stairs("concrete", Vector3(0.72, y + 1.5, zm), PI, 1.2, 1.5, run)
			b.stair_soffit(Vector3(0.72, y + 1.5, zm), PI, 1.2, 1.5, run)
			b.handrail(Vector3(-0.06, y, zf), Vector3(-0.06, y + 1.5, zm))
			b.handrail(Vector3(0.06, y + 1.5, zm), Vector3(0.06, y + 3.0, zf))
		# квартиры
		if fl == 0 or fl == nf:
			pass
		else:
			for sx in [-1.0, 1.0]:
				var x0: float = sx * (b.w * 0.5 - b.th)
				var x1: float = sx * 1.6
				b.floor_rect(y, minf(x0, x1), maxf(x0, x1), iz0, iz1)
		if fl < nf:
			for sx in [-1.0, 1.0]:
				var xo: float = sx * (b.w * 0.5 - b.th)
				var xi: float = sx * 1.6
				b.partition(Vector2(xi, zp), Vector2(xo, zp), fl, [[0.15, 0.15 + IDOOR_W]])
				if rng.randf() < 0.5:
					b.furn("bed", Vector3(xo - sx * 0.55, y, iz0 + 1.05))
					b.furn("wardrobe", Vector3(xi + sx * 0.6, y, iz0 + 0.33))
					b.furn("table", Vector3((xo + xi) * 0.5, y, (zp + iz1) * 0.5 + 0.2))
				b.pt("inside", Vector3((xo + xi) * 0.5, y, (zp + iz1) * 0.5))
	# крыша: две половины + будка над лестницей
	var yt := b.top_y()
	b.wall_ab(b.wall, Vector3(-1.6, yt, b.d * 0.5 - b.th * 0.5), Vector3(1.6, yt, b.d * 0.5 - b.th * 0.5), 2.8, b.th)
	b.wall_ab(b.wall, Vector3(-1.6, yt, -b.d * 0.5 + b.th * 0.5), Vector3(1.6, yt, -b.d * 0.5 + b.th * 0.5), 2.8, b.th)
	b.solid("concrete", Vector3(0, yt + 2.9, 0), Vector3(3.5, 0.2, b.d + 0.2))
	b.box(b.sill, Vector3(0, yt + 3.02, 0), Vector3(3.6, 0.04, b.d + 0.3))
	b.roof_flat(false, [[-1.6, 1.6, iz0, iz1]])
	b.roof_stuff(yt, [[-1.6, 1.6, -b.d, b.d]])
	b.dish(Vector3(1.7, yt + 2.4, b.d * 0.5 - 0.2), Vector3(0, 0, 1))
	# подъезд: скамейка, кондиционеры, тарелки
	b.furn("bench", Vector3(-2.4, 0, b.d * 0.5 + 1.3), PI)
	for k in rng.randi_range(2, 5):
		var fl := rng.randi_range(0, nf - 1)
		var u := rng.randf_range(2.0, b.w * 0.5 - 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		b.ac(2, b.tof(2, u), b.yk(fl) + 2.35)
	for k in rng.randi_range(1, 3):
		var fl2 := rng.randi_range(1, nf - 1)
		b.dish(Vector3(rng.randf_range(-b.w * 0.5 + 2.0, b.w * 0.5 - 2.0), b.yk(fl2) + 2.5, -b.d * 0.5 - 0.15), Vector3(0.3, 0, -1))
	b.stains(rng.randi_range(5, 9), b.top_y() - 0.5)
	b.corner_points()
	return b.info()


## Магазин / кафе: витрины с переплётом, маркиза, вывеска, прилавок или столики, подсобка, задняя дверь.
## opt.cafe (bool) — кафе.
static func shop(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	var cafe: bool = opt.get("cafe", rng.randf() < 0.4)
	b.w = snappedf(rng.randf_range(8.0, 10.0), 0.1)
	b.d = snappedf(rng.randf_range(7.6, 8.6), 0.1)
	b.fh = 3.4
	b.floor_y = 0.15
	b.parapet = 0.9
	b.wall = _pick(rng, walls_house)
	b.frame = "plate_dark"
	b.leaf = "plate_dark"
	b.jamb = "plate_dark"
	b.canopy = 0
	b.broken = 0.3
	b.grilles = rng.randf() < 0.5
	var ix0 := -b.w * 0.5 + b.th
	var ix1 := b.w * 0.5 - b.th
	var iz0 := -b.d * 0.5 + b.th
	var iz1 := b.d * 0.5 - b.th
	var pz := iz0 + 2.4
	var dx := rng.randf_range(-0.8, 0.8) - 0.7
	b.op_at(0, 0, dx, dx + 1.4, 0.0, DOOR_H, "door")
	var shows := [[ix0 + 0.5, dx - 0.4], [dx + 1.8, ix1 - 0.5]]
	b.op_at(0, 2, ix1 - 1.6, ix1 - 1.6 + DOOR_W, 0.0, DOOR_H, "door")
	b.spread(0, 1, pz + 0.3, iz1, 1, 1.2, 1.2, 2.3)
	b.spread(0, 3, pz + 0.3, iz1, 1, 1.2, 1.2, 2.3)
	b.spread(0, 3, iz0, pz, 1, 0.8, 1.5, 2.3)
	for sw in shows:
		if float(sw[1]) - float(sw[0]) > 1.2:
			b.op_at(0, 0, sw[0], sw[1], 0.5, 2.9, "shop")
	b.base_slab()
	b.walls()
	# витрины: частый переплёт, стекло (часть выбита), иногда опущенная рольставня
	var s0 := b.side(0)
	var a: Vector3 = s0[0]
	var bas := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	for sw in shows:
		var v0: float = sw[0]
		var v1: float = sw[1]
		if v1 - v0 <= 1.2:
			continue
		var y0 := b.floor_y + 0.5
		var y1 := b.floor_y + 2.9
		var cx := (v0 + v1) * 0.5
		var ww := v1 - v0
		var fo := b.th * 0.5 - 0.1
		var z := a.z
		var nv := maxi(2, int(ww / 1.1))
		for k in nv + 1:
			b.box("plate_dark", Vector3(v0 + ww * k / nv, (y0 + y1) * 0.5, z + fo), Vector3(0.07, y1 - y0, 0.1))
		for yy in [y0 + 0.03, y1 - 0.03, y0 + (y1 - y0) * 0.78]:
			b.box("plate_dark", Vector3(cx, yy, z + fo), Vector3(ww, 0.07, 0.1))
		for k in nv:
			if rng.randf() > b.broken:
				b.box("glass", Vector3(v0 + ww * (k + 0.5) / nv, (y0 + y1) * 0.5, z + fo - 0.02), Vector3(ww / nv - 0.06, y1 - y0 - 0.06, 0.012))
		b.box(b.sill, Vector3(cx, y0 - 0.02, z + b.th * 0.5 + 0.03), Vector3(ww + 0.08, 0.03, 0.18), false, bas * Basis(Vector3.RIGHT, 0.15))
		if rng.randf() < 0.45:
			var hd := rng.randf_range(0.5, 1.6)
			b.box("iron", Vector3(cx, y1 - hd * 0.5, z + b.th * 0.5 + 0.05), Vector3(hd, ww + 0.1, 0.04), false, Basis(Vector3.BACK, PI * 0.5))
			b.box("plate_dark", Vector3(cx, y1 + 0.15, z + b.th * 0.5 + 0.13), Vector3(ww + 0.2, 0.3, 0.26))
		b.pt("fire", Vector3(cx, b.floor_y, z - b.th * 0.5 - 0.8))
	# маркиза над витринами и вывеска
	var ay := b.floor_y + 3.15
	if rng.randf() < 0.7:
		b.box("canvas" if rng.randf() < 0.5 else "roof_red", Vector3(0, ay, b.d * 0.5 + 0.65), Vector3(b.w - 0.6, 0.03, 1.4), false, Basis(Vector3.RIGHT, 0.35))
		for sx in [-1.0, 1.0]:
			b.bar("plate_dark", Vector3(sx * (b.w * 0.5 - 0.35), ay + 0.25, b.d * 0.5), Vector3(sx * (b.w * 0.5 - 0.35), ay - 0.2, b.d * 0.5 + 1.3), Vector2(0.03, 0.03))
	b.box(_pick(rng, ["roof_red", "container_blue", "green"]), Vector3(0, b.top_y() + 0.35, b.d * 0.5 + 0.12), Vector3(b.w * 0.7, 0.8, 0.08))
	b.box("plate_dark", Vector3(0, b.top_y() + 0.35, b.d * 0.5 + 0.06), Vector3(b.w * 0.72, 0.86, 0.04))
	# интерьер: подсобка, прилавок/столики, стеллажи
	b.partition(Vector2(ix0, pz), Vector2(ix1, pz), 0, [[1.0, 1.0 + IDOOR_W]])
	var y := b.floor_y
	if cafe:
		for k in 3:
			var p := Vector3(ix0 + 1.4 + k * 2.4, y, pz + 2.0 + (k % 2) * 1.2)
			b.furn("table", p, rng.randf() * 0.4)
			b.furn("chair", p + Vector3(0, 0, 0.7), PI)
			b.furn("chair", p + Vector3(0, 0, -0.7), 0.0)
		b.furn("counter", Vector3(ix1 - 1.6, y, pz + 0.5))
	else:
		b.furn("counter", Vector3(ix0 + 1.8, y, pz + 1.9))
		for k in 3:
			b.furn("shelf", Vector3(ix0 + 2.8 + k * 1.1, y, pz + 0.26))
		b.furn("shelf", Vector3(ix1 - 0.25, y, pz + 1.4), -PI * 0.5)
		b.furn("shelf", Vector3(ix1 - 0.25, y, pz + 2.5), -PI * 0.5)
	b.furn("crate", Vector3(ix0 + 0.7, y, iz0 + 0.7))
	b.furn("crate", Vector3(ix0 + 1.6, y, iz0 + 0.6))
	b.furn("shelf", Vector3(ix0 + 3.0, y, iz0 + 0.25))
	b.roof_flat(true)
	b.ac(1, 1.0, b.floor_y + 2.6)
	b.stains(rng.randi_range(2, 4))
	b.pt("inside", Vector3(0, y, (pz + iz1) * 0.5))
	b.corner_points()
	return b.info()


## Склад / ангар: низ бетонный, выше профлист (простреливается), рольворота приоткрыты, ленточные окна,
## каркас и фермы, стеллажи с ящиками и паллеты. opt.w, opt.d — размеры.
static func warehouse(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	b.w = float(opt.get("w", snappedf(rng.randf_range(14.0, 18.0), 0.5)))
	b.d = float(opt.get("d", snappedf(rng.randf_range(10.0, 12.0), 0.5)))
	b.th = 0.3
	b.fh = 5.2
	b.floor_y = 0.08
	b.roof = "iron"
	b.frame = "plate_dark"
	b.leaf = "plate_dark"
	b.jamb = "plate_dark"
	b.canopy = 3
	b.broken = 0.35
	b.boarded = 0.0
	b.floor_mat = "concrete"
	var lo := 1.2
	var hw := b.w * 0.5
	var hd := b.d * 0.5
	var gx := rng.randf_range(-hw + 4.0, hw - 6.0)
	var gw := 4.4
	var gh := 4.2
	var px := gx + gw + 1.0
	b.base_slab()
	var fy := b.floor_y
	# стены: [a, b, n, проёмы-низ, проёмы-верх]; верх — профлист 0.1 у наружной грани
	var sides := [
		[Vector3(-hw, 0, hd - 0.15), Vector3(hw, 0, hd - 0.15), Vector3.BACK],
		[Vector3(hw - 0.15, 0, hd - 0.3), Vector3(hw - 0.15, 0, -hd + 0.3), Vector3.RIGHT],
		[Vector3(hw, 0, -hd + 0.15), Vector3(-hw, 0, -hd + 0.15), Vector3.FORWARD],
		[Vector3(-hw + 0.15, 0, -hd + 0.3), Vector3(-hw + 0.15, 0, hd - 0.3), Vector3.LEFT],
	]
	for si in 4:
		var sa: Vector3 = sides[si][0]
		var sb: Vector3 = sides[si][1]
		var n: Vector3 = sides[si][2]
		var ln := Vector2(sb.x - sa.x, sb.z - sa.z).length()
		var dir := (sb - sa).normalized()
		var low: Array = []
		var high: Array = []
		if si == 0:
			var t0 := gx + hw
			low.append([t0, t0 + gw, 0.0, lo])
			high.append([t0, t0 + gw, 0.0, gh - lo])
			var p0 := px + hw
			low.append([p0, p0 + DOOR_W, 0.0, lo])
			high.append([p0, p0 + DOOR_W, 0.0, DOOR_H - lo])
		if si == 2:
			var t2 := ln * 0.5 - 0.6
			low.append([t2, t2 + DOOR_W, 0.0, lo])
			high.append([t2, t2 + DOOR_W, 0.0, DOOR_H - lo])
		# ленточные окна под крышей на боковых и задней стенах
		var wins: Array = []
		if si != 0:
			var nw := int(ln / 3.2)
			for k in nw:
				var c := ln * (k + 0.5) / nw
				if si == 2 and absf(c - ln * 0.5) < 1.6:
					continue
				wins.append([c - 1.0, c + 1.0])
				high.append([c - 1.0, c + 1.0, 3.4 - lo, 4.3 - lo])
		var hi_a := sa + n * 0.09
		var hi_b := sb + n * 0.09
		if si == 1 or si == 3:
			hi_a += dir * -0.16
			hi_b += dir * 0.16
		b.wall_ab("concrete", sa + Vector3(0, fy, 0), sb + Vector3(0, fy, 0), lo, 0.3, low)
		b.wall_ab("iron", hi_a + Vector3(0, fy + lo, 0), hi_b + Vector3(0, fy + lo, 0), b.fh - lo, 0.1, high)
		if si % 2 == 1:
			b.box(b.sill, sa.lerp(sb, 0.5) + n * 0.17 + Vector3(0, fy + lo + 0.02, 0), Vector3(ln + 0.6, 0.04, 0.1), false,
				Basis(Vector3.UP, atan2(-dir.z, dir.x)))
		for wn in wins:
			b.win_at(hi_a, dir, n, 0.1, wn[0], wn[1], fy + 3.4, fy + 4.3, false, [], 0.0)
		# колонны каркаса изнутри (не в воротах и дверях)
		var nc := int(ln / 4.5)
		for k in nc + 1:
			var p := sa.lerp(sb, float(k) / nc) - n * 0.3
			if si == 0 and ((p.x > gx - 0.4 and p.x < gx + gw + 0.4) or (p.x > px - 0.4 and p.x < px + DOOR_W + 0.4)):
				continue
			if si == 2 and absf(p.x) < 1.0:
				continue
			b.box("plate_dark", p + Vector3(0, fy + b.fh * 0.5, 0), Vector3(0.22, b.fh, 0.22), true)
	# углы
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box("plate_dark", Vector3(sx * (hw - 0.08), fy + b.fh * 0.5 + 0.3, sz * (hd - 0.08)), Vector3(0.2, b.fh - 0.6, 0.2))
	# рольворота: короб, направляющие, полотно опущено на 20–40%
	var gc := Vector3(gx + gw * 0.5, 0, hd - 0.15)
	var drop := gh * rng.randf_range(0.15, 0.4)
	b.box("plate_dark", gc + Vector3(0, fy + gh + 0.3, -0.35), Vector3(gw + 0.4, 0.55, 0.5))
	for sd in [-1.0, 1.0]:
		b.box("plate_dark", gc + Vector3(sd * (gw * 0.5 + 0.05), fy + gh * 0.5, -0.25), Vector3(0.1, gh, 0.12))
	b.box("iron", gc + Vector3(0, fy + gh - drop * 0.5, -0.25), Vector3(drop, gw, 0.05), true, Basis(Vector3.BACK, PI * 0.5))
	b.box("plate_dark", gc + Vector3(0, fy + gh - drop, -0.25), Vector3(gw, 0.08, 0.08))
	b.box("concrete", gc + Vector3(0, -0.06, 1.2), Vector3(gw + 1.0, 0.24, 2.4), true, Basis(Vector3.RIGHT, -0.03))
	b.pt("doors", gc + Vector3(0, 0, 3.0))
	b.door_at(Vector3(-hw, 0, hd - 0.15), Vector3.RIGHT, Vector3.BACK, 0.3, px + hw, px + hw + DOOR_W, fy, fy + DOOR_H, b.leaf)
	b.entrance(Vector3(-hw, 0, hd - 0.15), Vector3.RIGHT, Vector3.BACK, px + hw, px + hw + DOOR_W, fy + DOOR_H)
	b.door_at(Vector3(hw, 0, -hd + 0.15), Vector3.LEFT, Vector3.FORWARD, 0.3, hw - 0.6, hw - 0.6 + DOOR_W, fy, fy + DOOR_H, b.leaf)
	b.entrance(Vector3(hw, 0, -hd + 0.15), Vector3.LEFT, Vector3.FORWARD, hw - 0.6, hw - 0.6 + DOOR_W, fy + DOOR_H)
	# крыша: пологая двускатная из профлиста + фермы
	var pitch := rng.randf_range(0.14, 0.22)
	var yr := b.roof_gable(pitch, 0.3, 0.25, "iron", false)
	var ye := b.top_y()
	var nt := int(b.w / 4.5)
	for k in range(1, nt):
		var x := -hw + b.w * k / nt
		b.box("plate_dark", Vector3(x, ye - 0.3, 0), Vector3(0.12, 0.16, b.d - 0.6))
		for sd in [-1.0, 1.0]:
			b.bar("plate_dark", Vector3(x, ye - 0.3, sd * (hd - 0.3)), Vector3(x, yr - 0.25, 0), Vector2(0.14, 0.1))
		b.bar("plate_dark", Vector3(x, ye - 0.3, 0), Vector3(x, yr - 0.25, 0), Vector2(0.08, 0.08))
	# стеллажи и паллеты
	var y := fy
	for row in [-1.0, 1.0]:
		var rz: float = row * (hd - 2.0) * 0.55 - 1.0
		var nr := int((b.w - 4.0) / 2.8)
		for k in nr:
			if rng.randf() < 0.15:
				continue
			b.furn("rack", Vector3(-nr * 1.4 + 1.4 + k * 2.8, y, rz))
	for k in rng.randi_range(3, 6):
		b.furn("pallet", Vector3(rng.randf_range(-hw + 1.5, hw - 1.5), y, rng.randf_range(hd - 3.6, hd - 1.6)), rng.randf() * 0.4)
	for k in rng.randi_range(2, 4):
		b.furn("crate", Vector3(rng.randf_range(-hw + 1.5, hw - 1.5), y, rng.randf_range(-hd + 1.0, -hd + 2.0)), rng.randf())
	b.furn("barrel", Vector3(hw - 1.0, y, hd - 1.0))
	b.furn("barrel", Vector3(hw - 1.6, y, hd - 0.9))
	b.pt("inside", Vector3(0, y, 0))
	b.pt("inside", Vector3(gc.x, y, hd - 3.0))
	b.pt("fire", Vector3(gc.x - gw * 0.5 + 0.4, y, hd - 1.0))
	b.corner_points()
	return b.info()


## Гаражи в ряд (1–4 бокса): бетонные стены, плоская крыша с рубероидом, распашные ворота
## (хотя бы один бокс открыт), внутри стеллаж, шины, верстак. opt.count — число боксов.
static func garages(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	var cnt := int(opt.get("count", rng.randi_range(2, 4)))
	var bw := 3.5
	b.th = 0.25
	b.w = cnt * bw + b.th
	b.d = 6.2
	b.fh = 2.6
	b.floor_y = 0.06
	b.wall = _pick(rng, ["concrete", "plaster", "plaster_tan"])
	var hw := b.w * 0.5
	var hd := b.d * 0.5
	b.base_slab(false)
	var fy := b.floor_y
	var open_k := rng.randi() % cnt
	var front_ops: Array = []
	for k in cnt:
		var x0 := -hw + k * bw
		var cx := x0 + bw * 0.5 + b.th * 0.5
		var gw := 2.6
		# фасад бокса: столбы по бокам ворот и перемычка
		var t0 := cx - gw * 0.5 + hw
		front_ops.append([t0, t0 + gw, 0.0, 2.25])
		# стены между боксами и торцы
		b.wall_ab(b.wall, Vector3(x0 + b.th * 0.5, fy, hd - b.th), Vector3(x0 + b.th * 0.5, fy, -hd + b.th), b.fh - 0.1, b.th)
		# ворота: две створки; закрытые — с коллизией
		var lm := _pick(rng, ["green", "rust", "container_blue", "plate_dark"])
		var state := 2 if k == open_k else rng.randi() % 3
		var gz := hd - b.th * 0.5
		for sd in [-1.0, 1.0]:
			var hinge := Vector3(cx + sd * gw * 0.5, fy + 1.1, gz + 0.02)
			var open: bool = state == 2 or (state == 1 and sd > 0)
			var ang: float = (rng.randf_range(1.4, 1.75) if open else 0.0) * sd
			var lb := Basis(Vector3.UP, ang)
			var lc := hinge + lb * Vector3(-sd * gw * 0.25, 0, 0.03)
			b.box(lm, lc, Vector3(gw * 0.5 - 0.02, 2.18, 0.04), not open, lb)
			b.box("plate_dark", lc + lb * Vector3(0, 0.9, 0.025), Vector3(gw * 0.5 - 0.06, 0.05, 0.02), false, lb)
		if state != 0:
			b.pt("doors", Vector3(cx, 0, hd + 1.5))
			b.pt("inside", Vector3(cx, fy, 0))
		var y := fy
		b.furn("shelf", Vector3(x0 + b.th + 0.25, y, -hd + 1.5), PI * 0.5)
		if rng.randf() < 0.7:
			b.furn("tire", Vector3(x0 + bw - 0.4, y, -hd + 0.7))
			b.furn("tire", Vector3(x0 + bw - 0.4, y + 0.24, -hd + 0.7))
		if rng.randf() < 0.6:
			b.furn("table", Vector3(cx, y, -hd + b.th + 0.4))
		if rng.randf() < 0.5:
			b.furn("barrel", Vector3(x0 + bw - 0.45, y, hd - 1.2))
		b.decal(Vector3(cx, fy + 2.45, hd + 0.012), Vector3.BACK, Vector3.RIGHT, Vector2(gw + 0.4, 0.5), 0)
	b.wall_ab(b.wall, Vector3(-hw, fy, hd - b.th * 0.5), Vector3(hw, fy, hd - b.th * 0.5), b.fh, b.th, front_ops)
	b.wall_ab(b.wall, Vector3(hw - b.th * 0.5, fy, hd - b.th), Vector3(hw - b.th * 0.5, fy, -hd + b.th), b.fh - 0.1, b.th)
	b.wall_ab(b.wall, Vector3(hw, fy, -hd + b.th * 0.5), Vector3(-hw, fy, -hd + b.th * 0.5), b.fh - 0.2, b.th)
	b.box("concrete", Vector3(0, fy + 0.005, 0), Vector3(b.w - 0.1, 0.01, b.d - 0.1))
	# крыша с уклоном назад, свес над воротами, рубероид
	var ry := fy + b.fh
	b.solid("concrete", Vector3(0, ry - 0.1, 0.15), Vector3(b.w + 0.2, 0.18, b.d + 0.5), Basis(Vector3.RIGHT, -0.02))
	b.box("asphalt", Vector3(0, ry + 0.0, 0.15), Vector3(b.w + 0.24, 0.02, b.d + 0.54), false, Basis(Vector3.RIGHT, -0.02))
	b.box("asphalt", Vector3(0, ry - 0.08, hd + 0.4), Vector3(b.w + 0.26, 0.2, 0.03))
	b.eave_streaks(ry - 0.15)
	b.stains(rng.randi_range(2, 4), 2.2)
	b.corner_points()
	b.floors = 1
	return b.info()


## Сарай / хозпостройка: дощатые (простреливаются) или жестяные стены, односкатная крыша,
## дверь на одной петле, поленница. opt.iron (bool) — из профлиста.
static func shed(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	b.w = snappedf(rng.randf_range(3.2, 4.4), 0.1)
	b.d = snappedf(rng.randf_range(2.8, 3.4), 0.1)
	b.th = 0.08
	b.floor_y = 0.12
	b.wall = "iron" if opt.get("iron", rng.randf() < 0.3) else _pick(rng, ["wood", "wood_dark"])
	b.roof = _pick(rng, ["iron", "slate", "roof_red"])
	b.floor_mat = "wood"
	b.frame = "wood_dark"
	b.boarded = 0.4
	b.broken = 0.4
	var hf := 2.6
	var hb := 2.15
	var hw := b.w * 0.5
	var hd := b.d * 0.5
	var fy := b.floor_y
	b.solid("wood_dark", Vector3(0, fy * 0.5 - 0.05, 0), Vector3(b.w, fy + 0.1, b.d))
	b.box("wood", Vector3(0, fy + 0.005, 0), Vector3(b.w - 0.16, 0.01, b.d - 0.16))
	var dx := rng.randf_range(-hw + 0.3, hw - 1.4)
	b.wall_ab(b.wall, Vector3(-hw, fy, hd - 0.04), Vector3(hw, fy, hd - 0.04), hf, b.th, [[dx + hw, dx + hw + 1.1, 0.0, 2.15]])
	b.wall_ab(b.wall, Vector3(hw, fy, -hd + 0.04), Vector3(-hw, fy, -hd + 0.04), hb, b.th, [[hw - 0.4 - 0.7, hw - 0.4, 1.1, 1.7]])
	b.win_at(Vector3(hw, 0, -hd + 0.04), Vector3.LEFT, Vector3.FORWARD, b.th, hw - 1.1, hw - 0.4, fy + 1.1, fy + 1.7)
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hw - 0.04)
		b.slab(b.wall, [Vector3(x, fy, hd - 0.08), Vector3(x, fy + hf, hd - 0.08), Vector3(x, fy + hb, -hd + 0.08), Vector3(x, fy, -hd + 0.08)],
			Vector3(sx, 0, 0), b.th, Vector3(0, 0, 1))
		b.col(Mats.surf(b.wall), Vector3(x, fy + (hf + hb) * 0.25, 0), Vector3(b.th, (hf + hb) * 0.5, b.d - 0.16))
		# угловые стойки
		for sz in [-1.0, 1.0]:
			b.box("wood_dark", Vector3(sx * (hw - 0.05), fy + (hf if sz > 0 else hb) * 0.5, sz * (hd - 0.05)), Vector3(0.1, hf if sz > 0 else hb, 0.1))
	b.door_at(Vector3(-hw, 0, hd - 0.04), Vector3.RIGHT, Vector3.BACK, b.th, dx + hw, dx + hw + 1.1, fy, fy + 2.15, "wood_dark")
	b.stairs("wood_dark", Vector3(dx + 0.55, 0, hd + 0.4), 0.0, 1.2, fy, 0.4)
	# односкатная крыша, свесы
	var ov := 0.35
	var pitch := atan2(hf - hb, b.d)
	var ln := (b.d + 2.0 * ov) / cos(pitch)
	var bas := Basis(Vector3.RIGHT, -pitch)
	b.solid(b.roof, Vector3(0, fy + (hf + hb) * 0.5 + 0.06, 0), Vector3(b.w + 0.5, 0.05, ln), bas)
	b.box("wood_dark", Vector3(0, fy + hf - 0.05, hd - 0.05), Vector3(b.w, 0.1, 0.1))
	b.box("wood_dark", Vector3(0, fy + hb - 0.05, -hd + 0.05), Vector3(b.w, 0.1, 0.1))
	if rng.randf() < 0.7:
		b.furn("firewood", Vector3(hw + 0.3, 0, 0), -PI * 0.5)
	b.furn("shelf", Vector3(hw - 0.3, fy, -0.3), -PI * 0.5)
	if rng.randf() < 0.6:
		b.furn("barrel", Vector3(-hw + 0.5, fy, -hd + 0.5))
	b.stains(rng.randi_range(1, 2), 1.8)
	b.pt("inside", Vector3(0, fy, 0))
	b.pt("doors", Vector3(dx + 0.55, 0, hd + 1.4))
	b.corner_points()
	return b.info()


## КПП / будка: остеклённая с трёх сторон, плоская крыша со свесом, табличка, фонарь,
## опционально шлагбаум (opt.boom) — вдоль +X от будки.
static func booth(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	b.w = 2.8
	b.d = 2.8
	b.th = 0.2
	b.fh = 2.7
	b.floor_y = 0.25
	b.wall = _pick(rng, ["plaster", "concrete", "stucco_blue"])
	b.frame = "plate_dark"
	b.broken = 0.3
	b.boarded = 0.0
	b.brow = 0.0
	b.grime = 0.15
	b.canopy = 0
	b.op_at(0, 0, -0.9, 0.9, 1.0, 2.25, "win")
	b.op_at(0, 1, -0.75, 0.75, 1.0, 2.25, "win")
	b.op_at(0, 2, -0.5, 0.5, 1.0, 2.25, "win")
	b.op_at(0, 3, -0.6, 0.6, 0.0, DOOR_H, "door")
	b.base_slab()
	b.walls()
	var y := b.floor_y
	b.floor_rect(b.top_y(), -b.w * 0.5 + b.th, b.w * 0.5 - b.th, -b.d * 0.5 + b.th, b.d * 0.5 - b.th, "-")
	b.box("iron", Vector3(0, b.top_y() + 0.06, 0), Vector3(b.w + 0.9, 0.12, b.d + 0.9), true)
	b.box("plate_dark", Vector3(0, b.top_y() - 0.04, 0), Vector3(b.w + 0.94, 0.1, b.d + 0.94))
	b.box("concrete", Vector3(0, b.top_y() + 0.32, b.d * 0.5 + 0.43), Vector3(1.4, 0.36, 0.04))
	b.box("roof_red", Vector3(0, b.top_y() + 0.32, b.d * 0.5 + 0.455), Vector3(1.2, 0.08, 0.01))
	b.box("!ffe2a0", Vector3(b.w * 0.5 + 0.2, b.top_y() - 0.25, b.d * 0.5 + 0.2), Vector3(0.18, 0.1, 0.18))
	b.furn("desk", Vector3(0, y, b.d * 0.5 - b.th - 0.4), PI)
	b.furn("chair", Vector3(0, y, b.d * 0.5 - b.th - 1.1))
	b.furn("cabinet", Vector3(-b.w * 0.5 + b.th + 0.3, y, -b.d * 0.5 + b.th + 0.35))
	b.pt("inside", Vector3(0.3, y, -0.2))
	if opt.get("boom", true):
		var bx := b.w * 0.5 + 0.8
		b.box("plate_dark", Vector3(bx, 0.55, b.d * 0.5 - 0.3), Vector3(0.3, 1.1, 0.3), true)
		var segs := 7
		for k in segs:
			b.box("roof_red" if k % 2 == 0 else "concrete", Vector3(bx + 0.3 + 0.6 * (k + 0.5), 1.0, b.d * 0.5 - 0.3), Vector3(0.6, 0.09, 0.09))
		b.box("plate_dark", Vector3(bx + 0.3 + 0.6 * segs - 0.05, 0.5, b.d * 0.5 - 0.3), Vector3(0.06, 1.0, 0.06))
	b.pt("fire", Vector3(0, y, b.d * 0.5 - b.th - 0.6))
	b.corner_points()
	return b.info()


## Штаб / административное здание в 2 этажа: портик с колоннами и балконом над входом, вестибюль
## с парадной лестницей, коридоры и кабинеты в крыльях, решётки на окнах, плоская крыша с мачтой.
static func hq(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	b.w = snappedf(rng.randf_range(16.0, 19.0), 0.2)
	b.d = 10.6
	b.fh = 3.2
	b.floors = 2
	b.floor_y = 0.5
	b.parapet = 0.8
	b.wall = _pick(rng, ["plaster_tan", "concrete", "stucco_yellow"])
	b.trim = "concrete"
	b.frame = "concrete"
	b.leaf = "wood_dark"
	b.grilles = true
	b.canopy = 0
	b.broken = 0.12
	b.rail = "concrete"
	var ix0 := -b.w * 0.5 + b.th
	var ix1 := b.w * 0.5 - b.th
	var iz0 := -b.d * 0.5 + b.th
	var iz1 := b.d * 0.5 - b.th
	var lx := 2.25
	var zs := iz1 - 2.35
	var rise := b.fh
	var run := 16 * 0.28
	# проёмы
	b.op_at(0, 0, -0.7, 0.7, 0.0, DOOR_H, "door")
	b.op_at(1, 0, -0.65, 0.65, 0.0, DOOR_H, "bdoor")
	for fl in 2:
		for sx in [-1.0, 1.0]:
			var e0: float = sx * (b.w * 0.5 - b.th)
			var e1: float = sx * (lx + 0.1)
			b.spread(fl, 0, e0, e1, int(absf(e1 - e0) / 2.2), 1.3)
			b.spread(fl, 2, e0, e1, int(absf(e1 - e0) / 2.2), 1.3)
		b.op_at(fl, 1, -0.55, 0.55, 0.9, 2.3, "win")
		b.op_at(fl, 3, -0.55, 0.55, 0.9, 2.3, "win")
		b.spread(fl, 2, -lx, lx, 1, 1.6, 0.9, 2.4)
	b.base_slab()
	b.walls()
	b.belts()
	# парадная лестница по центру вестибюля, к задней стене
	var y0 := b.floor_y
	b.stairs("concrete", Vector3(0, y0, zs), 0.0, 1.3, rise, run)
	b.stair_soffit(Vector3(0, y0, zs), 0.0, 1.3, rise, run)
	for sx in [-0.68, 0.68]:
		b.handrail(Vector3(sx, y0, zs), Vector3(sx, y0 + rise, zs - run), "wood_dark")
	var y1 := b.yk(1)
	b.floor_hole(y1, ix0, ix1, iz0, iz1, -0.7, 0.7, zs - run, zs - 1.0)
	for sx in [-0.72, 0.72]:
		b.box("wood_dark", Vector3(sx, y1 + 0.5, zs - run * 0.5 - 0.5), Vector3(0.05, 1.0, run - 1.0), true)
	b.box("wood_dark", Vector3(0, y1 + 0.5, zs - 1.0 + 0.03), Vector3(1.5, 1.0, 0.05), true)
	# стены вестибюля и коридоры с кабинетами
	for fl in 2:
		var y := b.yk(fl)
		for sx in [-1.0, 1.0]:
			var xl: float = sx * lx
			b.wall_ab(b.inner, Vector3(xl, y, iz1), Vector3(xl, y, iz0), b.fh - 0.2, 0.15, [[iz1 - 0.8, iz1 + 0.8, 0.0, DOOR_H]])
			var xo: float = sx * (b.w * 0.5 - b.th)
			var xi: float = sx * (lx + 0.075)
			var wl := absf(xo - xi)
			var nof := 2 if wl > 6.5 else 1
			for zc in [0.9, -0.9]:
				var drs: Array = []
				for k in nof:
					var c := wl * (k + 0.5) / nof
					drs.append([c - IDOOR_W * 0.5, c + IDOOR_W * 0.5])
				b.partition(Vector2(xi, zc), Vector2(xo, zc), fl, drs)
			if nof == 2:
				var xm := (xo + xi) * 0.5
				b.partition(Vector2(xm, iz1), Vector2(xm, 0.96), fl, [])
				b.partition(Vector2(xm, -0.96), Vector2(xm, iz0), fl, [])
			for k in nof:
				var ox := xi + (xo - xi) * (k + 0.5) / nof
				b.furn("desk", Vector3(ox, y, iz1 - 1.3), 0.0)
				b.furn("chair", Vector3(ox, y, iz1 - 0.7), PI)
				if k == 0:
					b.furn("cabinet", Vector3(ox + sx * 0.9, y, 1.3), PI)
				if fl == 0 or k == 0:
					b.furn("desk", Vector3(ox, y, iz0 + 1.3), PI)
				else:
					b.furn("shelf", Vector3(ox + sx * 1.0, y, -1.2), PI)
				b.pt("inside", Vector3(ox, y, iz1 - 2.0))
				b.pt("inside", Vector3(ox, y, iz0 + 2.0))
			b.pt("inside", Vector3((xo + xi) * 0.5, y, 0))
	# портик: площадка, колонны, балкон над входом
	var pw := 4.6
	var pd := 2.2
	var zf := b.d * 0.5
	b.solid("concrete", Vector3(0, (b.floor_y - 0.4) * 0.5, zf + pd * 0.5), Vector3(pw, b.floor_y + 0.4, pd))
	b.stairs("concrete", Vector3(0, 0, zf + pd + 0.9), 0.0, pw - 0.4, b.floor_y, 0.9)
	for sx in [-1.0, 1.0]:
		b.cyl("concrete", Vector3(sx * (pw * 0.5 - 0.3), b.floor_y + (y1 - b.floor_y) * 0.5, zf + pd - 0.3), 0.2, y1 - b.floor_y, 10, Basis(), -1.0, false, true)
		b.box("concrete", Vector3(sx * (pw * 0.5 - 0.3), b.floor_y + 0.1, zf + pd - 0.3), Vector3(0.5, 0.2, 0.5))
	b.solid("concrete", Vector3(0, y1 - 0.1, zf + pd * 0.5), Vector3(pw, 0.22, pd))
	b.box("concrete", Vector3(0, y1 + 0.006, zf + pd * 0.5), Vector3(pw - 0.1, 0.01, pd - 0.1))
	b.solid("concrete", Vector3(0, y1 + 0.5, zf + pd - 0.08), Vector3(pw, 1.0, 0.16))
	for sx in [-1.0, 1.0]:
		b.solid("concrete", Vector3(sx * (pw * 0.5 - 0.08), y1 + 0.5, zf + pd * 0.5), Vector3(0.16, 1.0, pd - 0.16))
	b.box(b.sill, Vector3(0, y1 + 1.02, zf + pd * 0.5), Vector3(pw + 0.04, 0.04, pd + 0.04))
	b.pt("fire", Vector3(0, y1, zf + pd * 0.5))
	b.pt("doors", Vector3(0, 0, zf + pd + 1.8))
	# мешки у входа
	for sx in [-1.0, 1.0]:
		for r in 3:
			for k in 4:
				b.box("sandbag", Vector3(sx * (pw * 0.5 + 0.9 + k * 0.6 + (0.3 if r % 2 == 1 else 0.0)), 0.1 + r * 0.19, zf + 1.6), Vector3(0.58, 0.2, 0.36), false,
					Basis(Vector3.UP, rng.randf_range(-0.07, 0.07)))
		b.col("dirt", Vector3(sx * (pw * 0.5 + 1.95), 0.28, zf + 1.6), Vector3(2.5, 0.56, 0.4))
		b.pt("cover", Vector3(sx * (pw * 0.5 + 1.95), 0, zf + 1.0))
	# крыша, мачта, флагшток, кондиционеры
	b.roof_flat(true)
	var yt := b.top_y()
	b.cyl("plate_dark", Vector3(ix1 - 1.5, yt + 3.0, iz0 + 1.5), 0.05, 6.0, 6, Basis(), -1.0, false)
	for k in 4:
		b.box("plate_dark", Vector3(ix1 - 1.5, yt + 3.8 + k * 0.5, iz0 + 1.5), Vector3(1.2 - k * 0.2, 0.025, 0.025), false, Basis(Vector3.UP, k * 0.5))
	b.cyl("plate_dark", Vector3(-pw * 0.5 - 2.6, 3.5, zf + 3.0), 0.05, 7.0, 6, Basis(), -1.0, false)
	b.box("roof_red", Vector3(-pw * 0.5 - 2.6 + 0.55, 6.6, zf + 3.0), Vector3(1.0, 0.65, 0.02))
	for k in rng.randi_range(3, 6):
		b.ac(2, rng.randf_range(1.5, b.w - 1.5), b.yk(rng.randi_range(0, 1)) + 2.75)
	b.stains(rng.randi_range(4, 7), 6.0)
	b.corner_points()
	return b.info()


## Руины дома: стены с рваным верхом и проломами, торчащая арматура, частично обрушенное перекрытие
## (наклонная плита — по ней можно забраться), груды обломков, копоть. opt.floors — 1 или 2.
static func ruin(g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}, opt := {}) -> Dictionary:
	var b := B.new(g, rng, pos, yaw, out)
	b.floors = int(opt.get("floors", rng.randi_range(1, 2)))
	b.w = snappedf(rng.randf_range(8.5, 11.0), 0.1)
	b.d = snappedf(rng.randf_range(7.0, 8.6), 0.1)
	b.fh = 3.0
	b.floor_y = 0.35
	b.wall = _pick(rng, ["plaster", "plaster_tan", "concrete"])
	b.frame = "wood_dark"
	b.broken = 0.85
	b.boarded = 0.1
	b.brow = 0.3
	b.soot = true
	b.grime = 0.15
	b.canopy = 0
	var ix0 := -b.w * 0.5 + b.th
	var ix1 := b.w * 0.5 - b.th
	var iz0 := -b.d * 0.5 + b.th
	var iz1 := b.d * 0.5 - b.th
	var mats := [b.wall, "concrete", "wood_dark"]
	b.op_at(0, 0, -0.5, -0.5 + DOOR_W, 0.0, DOOR_H, "door")
	for fl in b.floors:
		b.spread(fl, 0, ix0, -0.7, 1, 1.3)
		b.spread(fl, 0, 0.9, ix1, 2, 1.3)
		b.spread(fl, 2, ix0, ix1, 3, 1.3)
		b.spread(fl, 1, iz0, iz1, 2, 1.2)
		b.spread(fl, 3, iz0, iz1, 2, 1.2)
	b.base_slab()
	# стены с рваным верхом: каждая сторона — профиль высоты с провалами;
	# под уцелевшей частью перекрытия (x < xm) стены держатся выше него
	var hmax := b.fh * b.floors
	var xm := rng.randf_range(-0.8, 0.8)
	var keep := b.fh + 0.3 if b.floors > 1 else 0.0
	for si in 4:
		var s := b.side(si)
		var a: Vector3 = s[0]
		var dir: Vector3 = s[1]
		var n: Vector3 = s[2]
		var ln: float = s[3]
		var dips: Array = []
		for k in rng.randi_range(1, 3):
			dips.append([rng.randf_range(0.0, ln), rng.randf_range(1.0, 3.0), rng.randf_range(1.0, hmax + 0.5)])
		if si == 1 and rng.randf() < 0.6:
			dips.append([ln * 0.5, ln * 0.4, hmax])  # почти снесённая стена
		var cuts: Array = []
		for fl in b.floors:
			for o in b.ops.get(Vector2i(fl, si), []):
				cuts.append([o[0], o[1], b.yk(fl) - b.floor_y + float(o[2]), b.yk(fl) - b.floor_y + float(o[3])])
		var brk: Array = [0.0, ln]
		var u := 0.0
		while u < ln:
			u += rng.randf_range(0.45, 0.9)
			if u < ln - 0.2:
				brk.append(u)
		for c in cuts:
			brk.append(c[0])
			brk.append(c[1])
		brk.sort()
		for i in brk.size() - 1:
			var u0: float = brk[i]
			var u1: float = brk[i + 1]
			if u1 - u0 < 0.05:
				continue
			var um := (u0 + u1) * 0.5
			var top := clampf(Bld._ruin_top(dips, hmax, um) + rng.randf_range(-0.25, 0.25), 0.0, hmax)
			if keep > 0.0 and (a + dir * um).x < xm + 0.2:
				top = maxf(top, keep + rng.randf_range(0.0, 0.9))
			if top < 0.3:
				if rng.randf() < 0.6:
					b.rubble(a + dir * um - n * 0.3 + Vector3(0, b.floor_y, 0), 0.5, 0.4, 3, mats)
				continue
			var pieces: Array = [[0.0, top]]
			for c in cuts:
				if um > float(c[0]) and um < float(c[1]):
					var nxt: Array = []
					for pc in pieces:
						if float(pc[0]) < float(c[2]):
							nxt.append([pc[0], minf(float(pc[1]), float(c[2]))])
						if float(pc[1]) > float(c[3]):
							nxt.append([maxf(float(pc[0]), float(c[3])), pc[1]])
					pieces = nxt
			for pc in pieces:
				var p0: float = pc[0]
				var p1: float = pc[1]
				if p1 - p0 < 0.05:
					continue
				b.solid(b.wall, a + dir * um + Vector3(0, b.floor_y + (p0 + p1) * 0.5, 0), Vector3(u1 - u0, p1 - p0, b.th), Basis(dir, Vector3.UP, n))
			if top < hmax - 0.5 and rng.randf() < 0.3:
				for k in 2:
					var rp := a + dir * (um + rng.randf_range(-0.15, 0.15)) + Vector3(0, b.floor_y + top, 0) + n * rng.randf_range(-0.08, 0.08)
					b.bar("rust", rp - Vector3(0, 0.1, 0), rp + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.3, 0.6), rng.randf_range(-0.2, 0.2)), Vector2(0.025, 0.025))
		# обрамление уцелевших проёмов и копоть
		for fl in b.floors:
			for o in b.ops.get(Vector2i(fl, si), []):
				var yb := b.yk(fl)
				var wm := (float(o[0]) + float(o[1])) * 0.5
				var wtop := Bld._ruin_top(dips, hmax, wm) + b.floor_y
				if keep > 0.0 and (a + dir * wm).x < xm + 0.2:
					wtop = maxf(wtop, keep + b.floor_y)
				if wtop < yb + float(o[3]) + 0.5:
					pass
				elif String(o[4]) == "win" and rng.randf() < 0.6:
					b.win_at(a, dir, n, b.th, o[0], o[1], yb + float(o[2]), yb + float(o[3]), false, [], ln)
				elif wtop > yb + float(o[3]) + 1.2:
					b.decal(a + dir * ((float(o[0]) + float(o[1])) * 0.5) + Vector3(0, yb + float(o[3]) + 0.6, 0) + n * (b.th * 0.5 + 0.012),
						n, dir, Vector2(float(o[1]) - float(o[0]) + 0.6, 1.4), 0, true)
				if String(o[4]) == "door":
					b.entrance(a, dir, n, o[0], o[1], yb + float(o[3]))
	# перекрытие: левая часть цела, правая обрушена наклонно до земли
	if b.floors > 1:
		var y1 := b.yk(1)
		b.floor_rect(y1, ix0, xm, iz0, iz1, "-")
		var drop := y1 - b.floor_y - 0.4
		var span := ix1 - xm
		var ang := atan2(drop, span)
		var bas := Basis(Vector3.BACK, -ang)
		b.solid("concrete", Vector3((xm + ix1) * 0.5 + 0.1, b.floor_y + 0.4 + drop * 0.5, 0.3), Vector3(span / cos(ang), 0.2, b.d - 2.0 * b.th - 1.2), bas)
		b.rubble(Vector3(ix1 - 1.2, b.floor_y, 0.0), 1.4, 2.6, 18, mats, 0.4)
		b.pt("fire", Vector3((ix0 + xm) * 0.5, y1, iz1 - 0.8))
		b.pt("fire", Vector3((ix0 + xm) * 0.5, y1, iz0 + 0.8))
	# упавшие балки, обломки внутри, перегородка-обрубок
	for k in rng.randi_range(2, 4):
		var p0 := Vector3(rng.randf_range(ix0 + 0.5, ix1 - 0.5), b.floor_y + 0.1, rng.randf_range(iz0 + 0.5, iz1 - 0.5))
		var p1 := p0 + Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(0.2, 1.6), rng.randf_range(-2.0, 2.0))
		b.bar("wood_dark", p0, p1, Vector2(0.16, 0.12))
	b.rubble(Vector3(ix0 + 1.5, b.floor_y, iz0 + 1.3), 1.2, 1.0, 12, mats)
	b.rubble(Vector3(rng.randf_range(-1.0, 1.0), 0.0, -b.d * 0.5 - 0.8), 1.6, 0.9, 12, mats, 0.35)
	b.partition(Vector2(-1.2, iz0), Vector2(-1.2, iz0 + 2.6), 0, [], 0.12, b.wall, 1.6)
	b.pt("inside", Vector3(0, b.floor_y, 0))
	b.corner_points()
	return b.info()


## Высота руины в точке u вдоль стены: полная минус гауссовы провалы [центр, ширина, глубина].
static func _ruin_top(dips: Array, hmax: float, u: float) -> float:
	var top := hmax
	for dp in dips:
		top -= float(dp[2]) * exp(-pow((u - float(dp[0])) / float(dp[1]), 2.0))
	return top


## Построить здание по имени типа (для карт и предпросмотра).
## Типы: house, house_fence, house_east, house2, block, shop, cafe, warehouse, garages, shed, booth, hq, ruin.
static func build(kind: String, g: Geo, rng: RandomNumberGenerator, pos: Vector3, yaw := 0.0, out := {}) -> Dictionary:
	match kind:
		"house":
			return house(g, rng, pos, yaw, out)
		"house_fence":
			return house(g, rng, pos, yaw, out, {"fence": true})
		"house_east":
			return house(g, rng, pos, yaw, out, {"east": true})
		"house2":
			return house2(g, rng, pos, yaw, out)
		"block":
			return block(g, rng, pos, yaw, out)
		"shop":
			return shop(g, rng, pos, yaw, out, {"cafe": false})
		"cafe":
			return shop(g, rng, pos, yaw, out, {"cafe": true})
		"warehouse":
			return warehouse(g, rng, pos, yaw, out)
		"garages":
			return garages(g, rng, pos, yaw, out)
		"shed":
			return shed(g, rng, pos, yaw, out)
		"booth":
			return booth(g, rng, pos, yaw, out)
		"hq":
			return hq(g, rng, pos, yaw, out)
		"ruin":
			return ruin(g, rng, pos, yaw, out)
	push_warning("Bld.build: неизвестный тип %s" % kind)
	return {}


const TYPES := ["house", "house_fence", "house_east", "house2", "block", "shop", "cafe", "warehouse", "garages", "shed", "booth", "hq", "ruin"]
