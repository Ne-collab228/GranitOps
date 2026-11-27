class_name FPArms
extends RefCounted
## Руки от первого лица: рукав со складками и манжетой, тактическая перчатка с ладонью, костяшками и
## пальцами из трёх фаланг (большой — из двух), согнутыми под хват. Всё сливается в один меш на руку
## (3 поверхности: рукав, перчатка, накладки) — 3 вызова отрисовки вместо ~15 у прежних «коробок».
##
## grip: 0 — кулак на пистолетной рукоятке, 1 — ладонь снизу цевья, 2 — на вертикальной рукоятке.

static var _cap_cache := {}
static var _mats := {}


static func _mat(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"sleeve":
			var s := Mats.soldier("soldier_p").duplicate() as StandardMaterial3D
			s.uv1_scale = Vector3(0.24, 0.5, 1.0)
			s.emission_enabled = false
			m = s
		"glove":
			var g := (GunAssets.material("poly", "black") as StandardMaterial3D).duplicate() as StandardMaterial3D
			g.albedo_color = Color(0.085, 0.082, 0.075)
			g.roughness = 0.9
			g.uv1_scale = Vector3.ONE * 14.0
			m = g
		_:
			var p := (GunAssets.material("poly2", "black") as StandardMaterial3D).duplicate() as StandardMaterial3D
			p.albedo_color = Color(0.2, 0.19, 0.16)
			p.roughness = 0.75
			m = p
	_mats[kind] = m
	return m


static func _capsule(r: float, h: float) -> Mesh:
	var key := "%.4f_%.4f" % [r, h]
	if _cap_cache.has(key):
		return _cap_cache[key]
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.01)
	c.radial_segments = 8
	c.rings = 2
	_cap_cache[key] = c
	return c


static func _put(st: SurfaceTool, mesh: Mesh, xf: Transform3D) -> void:
	st.append_from(mesh, 0, xf)


## Цилиндр/конус между точками (ось меша Y -> направление a->b).
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, segs := 14) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = ra
	cm.top_radius = rb
	cm.height = maxf(0.001, a.distance_to(b))
	cm.radial_segments = segs
	cm.rings = 1
	_put(st, cm, Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5))


## Фаланга-капсула от точки p в направлении d длиной l.
static func _seg(st: SurfaceTool, p: Vector3, d: Vector3, l: float, r: float) -> Vector3:
	var e := p + d * l
	_put(st, _capsule(r, l + r * 2.0), Transform3D(Basis(Quaternion(Vector3.UP, d)), (p + e) * 0.5))
	return e


## Палец: цепочка фаланг, каждая повёрнута вокруг оси curl на свой угол.
static func _finger(st: SurfaceTool, base: Vector3, d0: Vector3, curl: Vector3, lens: Array, angs: Array, r: float) -> void:
	var p := base
	var a := 0.0
	for i in lens.size():
		a += float(angs[i])
		var d := d0.rotated(curl, a).normalized()
		p = _seg(st, p, d, float(lens[i]), r * (1.0 - i * 0.08))


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, basis := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_put(st, bm, Transform3D(basis, c))


## hs — масштаб кисти вокруг точки хвата (модель пистолета мельче настоящей — кисть уменьшается вместе с ней).
static func build(parent: Node3D, elbow: Vector3, wrist: Vector3, hand: Vector3, grip := 0, left := false, hs := 1.0) -> void:
	var sl := SurfaceTool.new()
	var gl := SurfaceTool.new()
	var pd := SurfaceTool.new()
	for st in [sl, gl, pd]:
		(st as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := -1.0 if left else 1.0
	var dir := (wrist - elbow).normalized()
	# рукав: чуть шире у локтя, две складки ткани
	_tube(sl, elbow - dir * 0.06, wrist - dir * 0.03, 0.058, 0.045)
	for k in [0.3, 0.62]:
		var p := elbow.lerp(wrist, k)
		_tube(sl, p - dir * 0.008, p + dir * 0.008, 0.056 - k * 0.012, 0.056 - k * 0.012)
	# манжета перчатки на запястье
	_tube(gl, wrist - dir * 0.04, wrist + dir * 0.012, 0.046, 0.041)
	_tube(pd, wrist - dir * 0.034, wrist - dir * 0.02, 0.048, 0.048)
	# запястье -> ладонь
	_tube(gl, wrist, wrist.lerp(hand, 0.65), 0.036, 0.034, 10)

	if grip == 1:
		# ладонь снизу цевья, пальцы обхватывают левый бок, большой — правый
		_box(gl, hand + Vector3(0, -0.004, 0), Vector3(0.068, 0.026, 0.082))
		_put(gl, _capsule(0.016, 0.08), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), hand + Vector3(-0.026 * sx, -0.006, 0)))
		for k in 4:
			var base := hand + Vector3(-0.03 * sx, 0.006, -0.03 + k * 0.02)
			var lens := [0.024, 0.019, 0.016] if k > 0 else [0.022, 0.017, 0.015]
			if k == 3:
				lens = [0.019, 0.015, 0.013]
			_finger(gl, base, Vector3(-0.85 * sx, 0.5, 0).normalized(), Vector3(0, 0, -sx), lens, [0.5, 0.75, 0.6], 0.0085)
			_box(pd, base + Vector3(-0.004 * sx, -0.004, 0), Vector3(0.01, 0.008, 0.016))
		_finger(gl, hand + Vector3(0.03 * sx, 0.002, 0.02), Vector3(0.45 * sx, 0.75, -0.45).normalized(), Vector3(0, 0, sx), [0.028, 0.022], [0.0, 0.35], 0.0105)
		_box(pd, hand + Vector3(0, -0.019, 0.006), Vector3(0.05, 0.006, 0.05))
	else:
		# кулак: ладонь сбоку рукоятки, пальцы огибают её спереди, большой палец сверху с другой стороны
		var axis := Vector3(0, -1, 0.28 if grip == 0 else 0.0).normalized()
		var fwd := Vector3(0, 0, -1)
		var palm_c := hand + Vector3(0.026 * sx, 0.0, 0.006)
		var pb := Basis(Vector3.RIGHT, -0.28 if grip == 0 else 0.0)
		_box(gl, palm_c, Vector3(0.026, 0.086, 0.066), pb)
		_put(gl, _capsule(0.015, 0.086), Transform3D(pb, palm_c + Vector3(0.006 * sx, 0, 0.026)))
		for k in 4:
			var t := 0.03 - k * 0.021
			var base := hand + Vector3(0.018 * sx, 0.0, -0.026) + axis * (-t)
			var lens := [0.024, 0.019, 0.016]
			if k == 3:
				lens = [0.019, 0.015, 0.013]
			_finger(gl, base, fwd, -axis * sx, lens, [0.35, 1.05, 0.95], 0.0088)
			_box(pd, base + Vector3(0.006 * sx, 0, -0.004), Vector3(0.012, 0.016, 0.01), pb)
		# большой палец: охватывает рукоятку сверху и ложится на другой бок
		# большой палец идёт вдоль противоположного бока вперёд, как при настоящем хвате
		var tb := hand + Vector3(0.004 * sx, 0.04, 0.022)
		_finger(gl, tb, Vector3(-0.42 * sx, 0.1, -0.9).normalized(), -axis * sx, [0.028, 0.022], [0.0, 0.18], 0.0102)
		# тыльная накладка на костяшках
		_box(pd, palm_c + Vector3(0.012 * sx, 0.005, -0.02), Vector3(0.008, 0.07, 0.024), pb)

	var mesh := ArrayMesh.new()
	var mats: Array = []
	for pair in [[sl, "sleeve"], [gl, "glove"], [pd, "pad"]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		st.commit(mesh)
		mats.append(pair[1])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not is_equal_approx(hs, 1.0):
		mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * hs), hand - hand * hs)
	for i in mats.size():
		mi.set_surface_override_material(i, Mats.viewmodel(_mat(mats[i])))
	parent.add_child(mi)
