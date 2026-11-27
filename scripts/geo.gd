class_name Geo
extends RefCounted
## Сборщик статичной геометрии: объединяет коробки/цилиндры в один меш на материал
## и создаёт физические тела по типам поверхностей.

# нормаль, ось U, ось V (U x V = -N)
const FACES := [
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0)],
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)],
]

## Высота земли (x, z) -> y для «контактного затенения»: низ стен и предметов темнее у земли.
static var ground_fn: Callable
var tools := {}
var shapes := {}
var cast_shadows := true

## Тени рисует не сам склеенный меш (он один на всю базу и на каждый материал — в тень попадали все
## его ~19 частей в каждом слое теней), а упрощённая копия: без материалов, кусками SHADOW_CELL м.
## В карту теней идут только куски рядом с игроком, по одному вызову отрисовки на кусок.
const SHADOW_CELL := 24.0
static var _shadow_mat: StandardMaterial3D


func _st(mat: String) -> SurfaceTool:
	if not tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[mat] = st
	return tools[mat]


func _shape(mat: String, shape: Shape3D, xf: Transform3D, kind := "") -> void:
	var k := kind if kind != "" else Mats.surf(mat)
	if not shapes.has(k):
		shapes[k] = []
	shapes[k].append([shape, xf])


func box(mat: String, center: Vector3, size: Vector3, yaw := 0.0, collide := true, pitch := 0.0, roll := 0.0) -> void:
	box_xf(mat, Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), center), size, collide)


func box_xf(mat: String, xf: Transform3D, size: Vector3, collide := true) -> void:
	var st := _st(mat)
	var h := size * 0.5
	var b := xf.basis
	var off := xf.origin
	for f in FACES:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var c := n * absf(n.dot(h))
		var wn := (b * n).normalized()
		var wt := (b * u).normalized()
		var ou := off.dot(wt)
		var ov := off.dot((b * v).normalized())
		var pts := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
		var uvs := [Vector2(-hu, -hv), Vector2(hu, -hv), Vector2(hu, hv), Vector2(-hu, hv)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(wn)
			st.set_tangent(Plane(wt, 1.0))
			st.set_uv(uvs[i] + Vector2(ou, ov))
			st.add_vertex(xf * pts[i])
	if collide:
		var s := BoxShape3D.new()
		s.size = size
		_shape(mat, s, xf)


## Цилиндр вдоль локальной оси Y.
func cyl(mat: String, xf: Transform3D, radius: float, height: float, segs := 12, collide := true, caps := true, radius_top := -1.0) -> void:
	var st := _st(mat)
	var hh := height * 0.5
	var b := xf.basis
	var rt := radius if radius_top < 0.0 else radius_top
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var t0 := Vector3(-sin(a0), 0, cos(a0))
		var t1 := Vector3(-sin(a1), 0, cos(a1))
		var u0 := a0 * radius
		var u1 := a1 * radius
		var quad := [
			[d0 * rt + Vector3(0, hh, 0), d0, t0, Vector2(u0, -hh)],
			[d0 * radius - Vector3(0, hh, 0), d0, t0, Vector2(u0, hh)],
			[d1 * radius - Vector3(0, hh, 0), d1, t1, Vector2(u1, hh)],
			[d1 * rt + Vector3(0, hh, 0), d1, t1, Vector2(u1, -hh)],
		]
		for k in [0, 1, 2, 0, 2, 3]:
			var q: Array = quad[k]
			st.set_normal((b * q[1]).normalized())
			st.set_tangent(Plane((b * q[2]).normalized(), -1.0))
			st.set_uv(q[3])
			st.add_vertex(xf * q[0])
		if caps:
			for side in [1.0, -1.0]:
				var nrm := (b * Vector3(0, side, 0)).normalized()
				var cr := rt if side > 0 else radius
				var tri := [Vector3(0, hh * side, 0), d0 * cr + Vector3(0, hh * side, 0), d1 * cr + Vector3(0, hh * side, 0)]
				var order := [0, 1, 2] if side > 0 else [0, 2, 1]
				for k in order:
					st.set_normal(nrm)
					st.set_tangent(Plane((b * Vector3(1, 0, 0)).normalized(), 1.0))
					st.set_uv(Vector2(tri[k].x, tri[k].z))
					st.add_vertex(xf * tri[k])
	if collide:
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		_shape(mat, s, xf)


## Эллипсоид (радиусы по локальным осям), без коллизии.
func sphere(mat: String, xf: Transform3D, radii: Vector3, segs := 12, rings := 7) -> void:
	var st := _st(mat)
	var b := xf.basis
	for r in rings:
		var p0 := PI * r / rings
		var p1 := PI * (r + 1) / rings
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var q := [[p0, a0], [p1, a0], [p1, a1], [p0, a1]]
			var order := [0, 2, 1, 0, 3, 2]
			for k in order:
				var ph: float = q[k][0]
				var th: float = q[k][1]
				var d := Vector3(sin(ph) * cos(th), cos(ph), sin(ph) * sin(th))
				st.set_normal((b * (d / radii)).normalized())
				st.set_tangent(Plane((b * Vector3(-sin(th), 0, cos(th))).normalized(), 1.0))
				st.set_uv(Vector2(th * radii.x, ph * radii.y))
				st.add_vertex(xf * (d * radii))


func cyl_at(mat: String, center: Vector3, radius: float, height: float, segs := 12, collide := true) -> void:
	cyl(mat, Transform3D(Basis(), center), radius, height, segs, collide)


## Невидимая коллизия (пандусы лестниц и т.п.).
func collider(kind: String, xf: Transform3D, size: Vector3) -> void:
	var s := BoxShape3D.new()
	s.size = size
	_shape("", s, xf, kind)


## Лестница: видимые ступени + наклонный пандус для ходьбы. Поднимается вдоль -Z локально.
func stairs(mat: String, base: Vector3, yaw: float, width: float, rise: float, run: float) -> void:
	var steps := int(ceil(rise / 0.2))
	var sh := rise / steps
	var sd := run / steps
	var rot := Basis(Vector3.UP, yaw)
	for i in steps:
		var c := base + rot * Vector3(0, sh * (i + 0.5), -sd * (i + 0.5))
		box_xf(mat, Transform3D(rot, c), Vector3(width, sh, sd), false)
	var ang := atan2(rise, run)
	var length := sqrt(rise * rise + run * run)
	var rb := rot * Basis(Vector3.RIGHT, ang)
	var center := base + rot * Vector3(0, rise * 0.5, -run * 0.5) - rb * Vector3(0, 0.06, 0)
	collider(Mats.surf(mat), Transform3D(rb, center), Vector3(width, 0.12, length + 0.15))


## Стена от a до b (основание) с проёмами [от, до, низ, верх] в метрах вдоль стены.
func wall(mat: String, a: Vector3, b: Vector3, height: float, thick: float, openings := []) -> void:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var dir := Vector3(d.x, 0, d.z).normalized()
	var yaw := atan2(-dir.z, dir.x)
	var cuts := openings.duplicate()
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var t := 0.0
	for o in cuts:
		var t0: float = clampf(o[0], 0.0, length)
		var t1: float = clampf(o[1], 0.0, length)
		if t0 > t + 0.01:
			_wall_seg(mat, a, dir, yaw, t, t0, 0.0, height, thick)
		if o[2] > 0.01:
			_wall_seg(mat, a, dir, yaw, t0, t1, 0.0, o[2], thick)
		if o[3] < height - 0.01:
			_wall_seg(mat, a, dir, yaw, t0, t1, o[3], height, thick)
		t = t1
	if t < length - 0.01:
		_wall_seg(mat, a, dir, yaw, t, length, 0.0, height, thick)


func _wall_seg(mat: String, a: Vector3, dir: Vector3, yaw: float, t0: float, t1: float, y0: float, y1: float, thick: float) -> void:
	var c := a + dir * ((t0 + t1) * 0.5) + Vector3(0, (y0 + y1) * 0.5, 0)
	box(mat, c, Vector3(t1 - t0, y1 - y0, thick), yaw)


## Создаёт MeshInstance3D и статичные тела. pen_kinds — типы поверхностей, простреливаемых пулей.
func finish(parent: Node3D, node_name := "geo") -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		if ground_fn.is_valid():
			# цвет вершин = затенение у земли (почти бесплатная замена SSAO на телефоне)
			var arr := st.commit_to_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols := PackedColorArray()
			cols.resize(verts.size())
			for i in verts.size():
				var v := verts[i]
				var h: float = v.y - float(ground_fn.call(v.x, v.z))
				var k := clampf(h / 1.4, 0.0, 1.0)
				var ao := lerpf(0.5, 1.0, k * k * (3.0 - 2.0 * k))
				cols[i] = Color(ao, ao, ao)
			arr[Mesh.ARRAY_COLOR] = cols
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		else:
			st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.get_mat(mat))
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if cast_shadows:
		shadow_proxies(parent, node_name, mesh)
	for kind in shapes:
		var body := StaticBody3D.new()
		body.name = "%s_%s" % [node_name, kind]
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		body.set_meta("surf", kind)
		parent.add_child(body)
		for pair in shapes[kind]:
			var cs := CollisionShape3D.new()
			cs.shape = pair[0]
			cs.transform = pair[1]
			body.add_child(cs)
	return mi


static func shadow_proxies(parent: Node3D, node_name: String, mesh: ArrayMesh) -> Array:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cells := {}
	for s in mesh.get_surface_count():
		# альфа-тест (сетка забора) копией не передать — такие поверхности тень не отбрасывают
		var mat := mesh.surface_get_material(s) as BaseMaterial3D
		if mat and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := idx.size() if not idx.is_empty() else verts.size()
		for t in range(0, n - 2, 3):
			var a := verts[idx[t] if not idx.is_empty() else t]
			var b := verts[idx[t + 1] if not idx.is_empty() else t + 1]
			var c := verts[idx[t + 2] if not idx.is_empty() else t + 2]
			var m := (a + b + c) / 3.0
			var key := Vector2i(floori(m.x / SHADOW_CELL), floori(m.z / SHADOW_CELL))
			if not cells.has(key):
				cells[key] = PackedVector3Array()
			var pv: PackedVector3Array = cells[key]
			pv.append(a)
			pv.append(b)
			pv.append(c)
			cells[key] = pv
	var out: Array = []
	for key in cells:
		var a2 := []
		a2.resize(Mesh.ARRAY_MAX)
		a2[Mesh.ARRAY_VERTEX] = cells[key]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		var smi := MeshInstance3D.new()
		smi.name = "%s_shadow" % node_name
		smi.mesh = am
		smi.material_override = _shadow_mat
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		parent.add_child(smi)
		out.append(smi)
	return out


## Треугольник с гарантированно лицевой (по часовой) ориентацией относительно нормали n.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv_scale := 4.0) -> void:
	var pts := [a, b, c]
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [a, c, b]
	for p in pts:
		st.set_normal(n)
		st.set_uv(Vector2(p.x + p.z, p.y) * uv_scale)
		st.add_vertex(p)


## Выдавленный по X профиль (точки в плоскости Z-Y) — для деталей оружия.
static func extrude(st: SurfaceTool, profile: PackedVector2Array, half_w: float, xf := Transform3D()) -> void:
	var idx := Geometry2D.triangulate_polygon(profile)
	for side in [1.0, -1.0]:
		var n := (xf.basis * Vector3(side, 0, 0)).normalized()
		for t in idx.size() / 3:
			var v := []
			for k in 3:
				var p := profile[idx[t * 3 + k]]
				v.append(xf * Vector3(half_w * side, p.y, p.x))
			tri(st, v[0], v[1], v[2], n)
	var flip := -1.0 if Geometry2D.is_polygon_clockwise(profile) else 1.0
	var m := profile.size()
	for i in m:
		var p0 := profile[i]
		var p1 := profile[(i + 1) % m]
		var e := p1 - p0
		if e.length() < 0.00001:
			continue
		var n2 := (xf.basis * (Vector3(0, -e.x, e.y) * flip)).normalized()
		var a := xf * Vector3(-half_w, p0.y, p0.x)
		var b := xf * Vector3(half_w, p0.y, p0.x)
		var c := xf * Vector3(half_w, p1.y, p1.x)
		var d := xf * Vector3(-half_w, p1.y, p1.x)
		tri(st, a, b, c, n2)
		tri(st, a, c, d, n2)


static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis()) -> void:
	var h := size * 0.5
	for f in FACES:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var c := n * absf(n.dot(h))
		var pts := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(basis * n)
			st.set_uv(Vector2(pts[i].dot(u), pts[i].dot(v)) * 4.0)
			st.add_vertex(center + basis * pts[i])


static func add_cyl(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, height: float, segs := 10) -> void:
	var hh := height * 0.5
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var quad := [
			[d0 * r1 + Vector3(0, hh, 0), d0], [d0 * r0 - Vector3(0, hh, 0), d0],
			[d1 * r0 - Vector3(0, hh, 0), d1], [d1 * r1 + Vector3(0, hh, 0), d1],
		]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal((xf.basis * quad[k][1]).normalized())
			st.set_uv(Vector2(float(i) / segs, 0.5))
			st.add_vertex(xf * quad[k][0])
		for side in [1.0, -1.0]:
			var r := r1 if side > 0 else r0
			var tri_pts := [Vector3(0, hh * side, 0), d0 * r + Vector3(0, hh * side, 0), d1 * r + Vector3(0, hh * side, 0)]
			var order := [0, 1, 2] if side > 0 else [0, 2, 1]
			for k in order:
				st.set_normal((xf.basis * Vector3(0, side, 0)).normalized())
				st.set_uv(Vector2(0.5, 0.5))
				st.add_vertex(xf * tri_pts[k])
