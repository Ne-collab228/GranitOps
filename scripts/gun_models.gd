class_name GunModels
extends RefCounted
## Модели оружия от первого лица. Длинноствольное оружие собирается процедурно из профилей
## и призм с учётом обвеса; винтовка СВ-7 и пистолет — модели CC0 (Poly Haven).
##
## Система координат: ствол смотрит в -Z, ось канала ствола на высоте BORE, верх ствольной коробки y = 0.

const BORE := -0.02
const CAMO := {
	"black": [Color(0.07, 0.07, 0.075), Color(0.04, 0.04, 0.042)],
	"sand": [Color(0.4, 0.33, 0.23), Color(0.05, 0.05, 0.05)],
	"olive": [Color(0.2, 0.24, 0.14), Color(0.05, 0.055, 0.045)],
	"grey": [Color(0.33, 0.34, 0.36), Color(0.09, 0.09, 0.1)],
	"arctic": [Color(0.78, 0.8, 0.82), Color(0.2, 0.21, 0.22)],
	"wood": [Color(0.34, 0.18, 0.09), Color(0.05, 0.05, 0.05)],
}

static var _sleeve: StandardMaterial3D


## Сборщик геометрии по группам материалов.
class B:
	var st := {}

	func s(k: String) -> SurfaceTool:
		if not st.has(k):
			var t := SurfaceTool.new()
			t.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[k] = t
		return st[k]

	func box(k: String, c: Vector3, size: Vector3, basis := Basis()) -> void:
		Geo.add_box(s(k), c, size, basis)

	## Цилиндр/конус вдоль Z: от za (радиус ra) до zb (радиус rb).
	func cz(k: String, za: float, zb: float, y: float, ra: float, rb := -1.0, segs := 10, x := 0.0) -> void:
		if rb < 0.0:
			rb = ra
		var front := minf(za, zb)
		var rear := maxf(za, zb)
		var rf := ra if za < zb else rb
		var rr := rb if za < zb else ra
		Geo.add_cyl(s(k), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, (front + rear) * 0.5)), rf, rr, rear - front, segs)

	## Вертикальный цилиндр.
	func cy(k: String, c: Vector3, r0: float, r1: float, h: float, segs := 10) -> void:
		Geo.add_cyl(s(k), Transform3D(Basis(), c), r0, r1, h, segs)

	## Профиль (z, y), выдавленный по X.
	func ex(k: String, pts: Array, hw: float, x := 0.0) -> void:
		var p := PackedVector2Array()
		for q in pts:
			p.append(Vector2(q[0], q[1]))
		Geo.extrude(s(k), p, hw, Transform3D(Basis(), Vector3(x, 0, 0)))

	## Призма вдоль Z с сечением pts (x, y).
	func prism(k: String, pts: PackedVector2Array, z0: float, z1: float) -> void:
		var t := s(k)
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		for i in pts.size():
			var p0 := pts[i]
			var p1 := pts[(i + 1) % pts.size()]
			var e := p1 - p0
			var n := Vector3(e.y, -e.x, 0).normalized()
			if n.dot(Vector3(((p0 + p1) * 0.5 - c).x, ((p0 + p1) * 0.5 - c).y, 0)) < 0.0:
				n = -n
			var a := Vector3(p0.x, p0.y, z0)
			var b2 := Vector3(p1.x, p1.y, z0)
			var c2 := Vector3(p1.x, p1.y, z1)
			var d := Vector3(p0.x, p0.y, z1)
			Geo.tri(t, a, b2, c2, n)
			Geo.tri(t, a, c2, d, n)
		for z in [z0, z1]:
			var nz := Vector3(0, 0, 1.0 if z == maxf(z0, z1) else -1.0)
			for i in range(1, pts.size() - 1):
				Geo.tri(t, Vector3(pts[0].x, pts[0].y, z), Vector3(pts[i].x, pts[i].y, z), Vector3(pts[i + 1].x, pts[i + 1].y, z), nz)

	## Брусок со снятыми фасками вдоль Z (сечение — восьмиугольник).
	func oct(k: String, z0: float, z1: float, cy0: float, hx: float, hy: float, ch: float, x := 0.0) -> void:
		prism(k, PackedVector2Array([
			Vector2(x - hx + ch, cy0 + hy), Vector2(x + hx - ch, cy0 + hy), Vector2(x + hx, cy0 + hy - ch), Vector2(x + hx, cy0 - hy + ch),
			Vector2(x + hx - ch, cy0 - hy), Vector2(x - hx + ch, cy0 - hy), Vector2(x - hx, cy0 - hy + ch), Vector2(x - hx, cy0 + hy - ch)]), z0, z1)

	## Планка Пикатинни: основание и зубцы. Возвращает высоту верха планки.
	func rail(z0: float, z1: float, y: float, k := "metal") -> float:
		var a := minf(z0, z1)
		var b2 := maxf(z0, z1)
		box(k, Vector3(0, y + 0.002, (a + b2) * 0.5), Vector3(0.017, 0.004, b2 - a))
		var z := a + 0.004
		while z < b2 - 0.003:
			box(k, Vector3(0, y + 0.006, z), Vector3(0.021, 0.004, 0.0055))
			z += 0.0105
		return y + 0.008

	func commit(parent: Node3D, mats: Dictionary) -> void:
		for k in st:
			var mi := MeshInstance3D.new()
			mi.mesh = (st[k] as SurfaceTool).commit()
			mi.material_override = Mats.viewmodel(mats[k])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)


static func _mats(camo: String) -> Dictionary:
	var c: Array = CAMO.get(camo, CAMO.black)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.45, 0.75, 0.85, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return {
		"metal": Mats.flat(Color(0.1, 0.1, 0.105), 0.5, 0.25),
		"poly": Mats.flat(c[1], 0.62, 0.0),
		"furn": Mats.flat(c[0], 0.74 if camo != "wood" else 0.5, 0.0),
		"dark": Mats.flat(Color(0.012, 0.012, 0.012), 0.9, 0.0),
		"brass": Mats.flat(Color(0.62, 0.46, 0.18), 0.4, 0.7),
		"red": Mats.emissive(Color(1.0, 0.12, 0.06), 1.6),
		"glass": glass,
	}


static func _add(parent: Node3D, mesh: Mesh, mat: Material, xf := Transform3D()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Mats.viewmodel(mat)
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _apply_vm(model: Node) -> void:
	for n in Mats.mesh_instances(model):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, Mats.viewmodel(mi.mesh.surface_get_material(i)))


static func _between(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, mat: Material, segs := 12) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = ra
	cm.top_radius = rb
	cm.height = a.distance_to(b)
	cm.radial_segments = segs
	cm.rings = 1
	_add(parent, cm, mat, Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5))


## Рука: рукав с манжетой от локтя до запястья и перчатка с пальцами.
## grip: 0 — кисть на пистолетной рукоятке, 1 — кисть снизу на цевье, 2 — на вертикальной рукоятке.
static func _arm(parent: Node3D, elbow: Vector3, wrist: Vector3, hand: Vector3, grip := 0, left := false, k := 1.0) -> void:
	FPArms.build(parent, elbow, wrist, hand, grip, left, k)


static func _scale_mag(pts: Array, top: float, k: float) -> Array:
	var out: Array = []
	for p in pts:
		out.append([p[0] + (p[1] - top) * (k - 1.0) * 0.18, top + (p[1] - top) * k])
	return out


# ------------------------------------------------------------------ части
static func _trigger(b: B, z: float, y: float) -> void:
	b.box("metal", Vector3(0, y - 0.038, z), Vector3(0.008, 0.003, 0.078))
	b.box("metal", Vector3(0, y - 0.02, z - 0.038), Vector3(0.008, 0.038, 0.003), Basis(Vector3.RIGHT, -0.35))
	b.box("metal", Vector3(0, y - 0.018, z + 0.004), Vector3(0.005, 0.028, 0.006), Basis(Vector3.RIGHT, 0.3))


static func _grip(b: B, z: float, y: float, k := "furn") -> void:
	b.ex(k, [[z - 0.027, y], [z + 0.016, y], [z + 0.03, y - 0.04], [z + 0.058, y - 0.104], [z + 0.018, y - 0.112], [z - 0.004, y - 0.045]], 0.0135)
	b.box("poly", Vector3(0, y - 0.11, z + 0.038), Vector3(0.029, 0.006, 0.044), Basis(Vector3.RIGHT, -0.13))


## Механический прицел: целик с прорезью и мушка в кольце. base_* — на какой высоте стоят основания.
static func _irons(b: B, rear_z: float, rear_base: float, front_z: float, front_base: float, axis: float) -> void:
	b.box("metal", Vector3(0, (rear_base + axis - 0.006) * 0.5, rear_z), Vector3(0.02, axis - 0.006 - rear_base, 0.014))
	for sx in [-0.0065, 0.0065]:
		b.box("metal", Vector3(sx, axis + 0.001, rear_z), Vector3(0.005, 0.014, 0.006))
	b.box("metal", Vector3(0, axis + 0.0095, rear_z), Vector3(0.018, 0.003, 0.006))
	b.box("metal", Vector3(0, (front_base + axis - 0.012) * 0.5, front_z), Vector3(0.012, maxf(0.004, axis - 0.012 - front_base), 0.016))
	b.box("metal", Vector3(0, axis - 0.007, front_z), Vector3(0.0028, 0.014, 0.0028))
	for sx in [-0.009, 0.009]:
		b.box("metal", Vector3(sx, axis - 0.004, front_z), Vector3(0.003, 0.024, 0.008))


## Дульное устройство. Возвращает координату Z дульного среза.
static func _muzzle(b: B, kind: String, z: float, r: float, y := BORE) -> float:
	match kind:
		"flash":
			b.cz("metal", z + 0.004, z - 0.046, y, r + 0.0045, r + 0.0038, 10)
			for a in 3:
				var ang := a * TAU / 3.0 + 0.5
				b.box("dark", Vector3(cos(ang) * (r + 0.0044), y + sin(ang) * (r + 0.0044), z - 0.024), Vector3(0.0035, 0.0035, 0.03), Basis(Vector3.FORWARD, -ang))
			return z - 0.046
		"comp":
			b.oct("metal", z + 0.004, z - 0.058, y, r + 0.008, r + 0.0065, 0.004)
			for i in 3:
				for sx in [-1.0, 1.0]:
					b.box("dark", Vector3(sx * (r + 0.0082), y, z - 0.012 - i * 0.015), Vector3(0.001, 0.007, 0.008))
				b.box("dark", Vector3(0, y + r + 0.0067, z - 0.012 - i * 0.015), Vector3(0.008, 0.001, 0.008))
			return z - 0.058
		"supp":
			b.cz("poly", z + 0.022, z - 0.15, y, 0.0178, 0.0178, 14)
			b.cz("metal", z + 0.03, z + 0.022, y, 0.0135, 0.0165, 12)
			b.cz("metal", z - 0.15, z - 0.156, y, 0.0178, 0.014, 14)
			for i in 4:
				b.cz("metal", z - 0.01 - i * 0.034, z - 0.014 - i * 0.034, y, 0.0183, 0.0183, 14)
			b.cz("dark", z - 0.1562, z - 0.1568, y, 0.006, 0.006, 8)
			return z - 0.157
	b.cz("metal", z + 0.002, z - 0.012, y, r + 0.002, r + 0.002, 10)
	return z - 0.012


## Прицел на планке. Возвращает высоту оптической оси.
static func _optic(b: B, glass: Array, kind: String, y0: float, oz: float) -> float:
	match kind:
		"rds":
			var ax := y0 + 0.03
			b.box("poly", Vector3(0, y0 + 0.006, oz), Vector3(0.03, 0.012, 0.052))
			for sx in [-0.0175, 0.0175]:
				b.box("poly", Vector3(sx, ax + 0.002, oz), Vector3(0.0045, 0.04, 0.044))
			b.box("poly", Vector3(0, ax + 0.0235, oz), Vector3(0.0395, 0.0045, 0.044))
			for sx in [-0.0155, 0.0155]:
				b.box("poly", Vector3(sx, ax + 0.019, oz), Vector3(0.007, 0.007, 0.044), Basis(Vector3.FORWARD, 0.785))
			b.cz("poly", oz + 0.014, oz + 0.002, y0 + 0.02, 0.0065, 0.0065, 8, 0.024)
			b.box("metal", Vector3(0.0, ax + 0.028, oz + 0.008), Vector3(0.012, 0.006, 0.012))
			glass.append([Vector3(0, ax, oz - 0.012), Vector2(0.031, 0.04)])
			return ax
		"holo":
			var ax2 := y0 + 0.037
			b.box("poly", Vector3(0, y0 + 0.011, oz + 0.016), Vector3(0.038, 0.022, 0.09))
			b.box("metal", Vector3(0.021, y0 + 0.012, oz + 0.03), Vector3(0.006, 0.016, 0.03))
			for sx in [-0.0215, 0.0215]:
				b.box("poly", Vector3(sx, ax2 + 0.001, oz - 0.01), Vector3(0.0045, 0.034, 0.044))
			b.box("poly", Vector3(0, ax2 + 0.019, oz - 0.01), Vector3(0.0475, 0.0045, 0.044))
			for sx in [-0.0255, 0.0255]:
				b.box("metal", Vector3(sx, ax2 - 0.002, oz - 0.01), Vector3(0.003, 0.03, 0.05))
			b.box("poly", Vector3(0, y0 + 0.012, oz + 0.066), Vector3(0.03, 0.02, 0.012))
			glass.append([Vector3(0, ax2, oz - 0.02), Vector2(0.039, 0.033)])
			return ax2
		"x3":
			var ax3 := y0 + 0.036
			b.box("poly", Vector3(0, y0 + 0.009, oz), Vector3(0.024, 0.018, 0.075))
			b.oct("poly", oz + 0.062, oz - 0.052, ax3, 0.0175, 0.0175, 0.007)
			b.cz("poly", oz - 0.052, oz - 0.092, ax3, 0.0185, 0.023, 12)
			b.cz("poly", oz + 0.092, oz + 0.062, ax3, 0.0195, 0.0195, 12)
			b.cz("dark", oz + 0.0925, oz + 0.093, ax3, 0.016, 0.016, 12)
			b.box("red", Vector3(0, ax3 + 0.0185, oz + 0.01), Vector3(0.005, 0.003, 0.062))
			b.box("metal", Vector3(0.02, ax3, oz + 0.02), Vector3(0.008, 0.014, 0.014))
			glass.append([Vector3(0, ax3, oz - 0.0925), Vector2(0.04, 0.04)])
			return ax3
		"x6", "x10":
			var ax4 := y0 + 0.04
			var ext := 0.045 if kind == "x10" else 0.0
			var bell := 0.029 if kind == "x10" else 0.025
			b.cz("poly", oz + 0.11, oz - 0.13 - ext, ax4, 0.0135, 0.0135, 12)
			b.cz("poly", oz - 0.13 - ext, oz - 0.195 - ext, ax4, 0.0135, bell, 12)
			b.cz("poly", oz - 0.195 - ext, oz - 0.24 - ext, ax4, bell, bell, 12)
			b.cz("poly", oz + 0.11, oz + 0.125, ax4, 0.0135, 0.0195, 12)
			b.cz("poly", oz + 0.125, oz + 0.18, ax4, 0.0195, 0.0195, 12)
			b.cz("dark", oz + 0.1805, oz + 0.181, ax4, 0.016, 0.016, 12)
			b.cy("metal", Vector3(0, ax4 + 0.023, oz - 0.01), 0.0105, 0.0105, 0.02, 10)
			b.cz("metal", oz - 0.0, oz - 0.02, ax4, 0.0105, 0.0105, 10, 0.024)
			b.box("poly", Vector3(0, ax4, oz - 0.01), Vector3(0.032, 0.032, 0.03))
			for rz in [oz + 0.06, oz - 0.085]:
				b.box("metal", Vector3(0, y0 + 0.014, rz), Vector3(0.024, 0.028, 0.016))
				b.cz("metal", rz + 0.008, rz - 0.008, ax4, 0.0165, 0.0165, 10)
			glass.append([Vector3(0, ax4, oz - 0.2405 - ext), Vector2(bell * 1.8, bell * 1.8)])
			return ax4
	return y0


static func _foregrip(b: B, kind: String, z: float, y: float) -> void:
	if kind == "vert":
		b.box("poly", Vector3(0, y - 0.005, z), Vector3(0.024, 0.01, 0.042))
		b.cy("poly", Vector3(0, y - 0.05, z), 0.0135, 0.0125, 0.085, 10)
		b.cy("metal", Vector3(0, y - 0.095, z), 0.0145, 0.0145, 0.006, 10)
	elif kind == "angled":
		b.ex("poly", [[z + 0.055, y], [z - 0.06, y], [z - 0.05, y - 0.016], [z + 0.012, y - 0.044], [z + 0.05, y - 0.04]], 0.012)


static func _laser(b: B, z: float, x: float, y: float) -> void:
	b.box("poly", Vector3(x, y, z), Vector3(0.018, 0.024, 0.056))
	b.cz("metal", z - 0.028, z - 0.034, y + 0.003, 0.006, 0.006, 8, x)
	b.box("red", Vector3(x, y + 0.003, z - 0.0345), Vector3(0.005, 0.005, 0.001))
	b.box("metal", Vector3(x, y + 0.014, z + 0.012), Vector3(0.008, 0.005, 0.01))


static func _stock_generic(b: B, kind: String, z0: float, top: float, length: float, drop: float) -> void:
	var z1 := z0 + length
	if kind == "light":
		b.ex("furn", [[z0, top], [z1, top - 0.012], [z1, top - 0.03], [z0, top - 0.02]], 0.011)
		b.ex("furn", [[z0 + 0.03, top - 0.045], [z1, top - drop + 0.012], [z1, top - drop], [z0 + 0.03, top - 0.06]], 0.009)
		b.box("poly", Vector3(0, top - drop * 0.5, z1 + 0.004), Vector3(0.03, drop + 0.01, 0.01))
		return
	b.ex("furn", [[z0, top], [z1, top - 0.022], [z1 + 0.004, top - drop * 0.5], [z1, top - drop], [z1 - 0.03, top - drop - 0.002],
		[z0 + 0.07, top - 0.052], [z0, top - 0.048]], 0.0165)
	b.box("poly", Vector3(0, top - drop * 0.5 - 0.008, z1 + 0.007), Vector3(0.036, drop + 0.004, 0.012))
	if kind == "heavy":
		b.oct("furn", z0 + 0.06, z1 - 0.05, top + 0.004, 0.015, 0.014, 0.006)
		b.box("poly", Vector3(0, top - drop * 0.5 - 0.008, z1 + 0.016), Vector3(0.04, drop + 0.012, 0.008))


# ------------------------------------------------------------------ оружие
static func _ar(b: B, mb: B, att: Dictionary) -> Dictionary:
	b.oct("metal", 0.03, -0.21, -0.018, 0.018, 0.018, 0.006)
	b.ex("metal", [[0.03, -0.034], [-0.165, -0.034], [-0.168, -0.092], [-0.105, -0.092], [-0.105, -0.068], [-0.02, -0.068], [0.03, -0.05]], 0.0165)
	_trigger(b, -0.055, -0.066)
	_grip(b, 0.004, -0.062)
	b.cz("metal", 0.26, 0.03, -0.018, 0.0125, 0.0125, 12)
	b.cz("metal", 0.05, 0.03, -0.018, 0.018, 0.018, 12)
	b.box("metal", Vector3(0, -0.002, 0.036), Vector3(0.052, 0.007, 0.012))
	b.box("dark", Vector3(0.0183, -0.02, -0.1), Vector3(0.001, 0.014, 0.062))
	b.box("metal", Vector3(0.0195, -0.02, -0.058), Vector3(0.006, 0.014, 0.012))
	b.box("metal", Vector3(0.021, -0.012, -0.02), Vector3(0.008, 0.01, 0.016))
	b.box("metal", Vector3(-0.0175, -0.046, -0.004), Vector3(0.003, 0.006, 0.022))
	b.box("metal", Vector3(0.0175, -0.052, -0.09), Vector3(0.003, 0.01, 0.008))
	b.box("metal", Vector3(-0.0175, -0.045, -0.1), Vector3(0.003, 0.02, 0.012))
	match att.get("stock", "std"):
		"light":
			b.ex("furn", [[0.1, 0.002], [0.27, 0.002], [0.272, -0.118], [0.256, -0.12], [0.244, -0.04], [0.1, -0.036]], 0.0155)
			b.box("poly", Vector3(0, -0.058, 0.276), Vector3(0.03, 0.125, 0.008))
		_:
			b.ex("furn", [[0.1, 0.004], [0.275, 0.004], [0.28, -0.02], [0.28, -0.125], [0.25, -0.13], [0.2, -0.062], [0.1, -0.042]], 0.019)
			b.box("poly", Vector3(0, -0.06, 0.285), Vector3(0.036, 0.136, 0.011))
			b.box("poly", Vector3(0, -0.05, 0.15), Vector3(0.012, 0.01, 0.05))
			if att.get("stock", "std") == "heavy":
				b.oct("furn", 0.12, 0.25, 0.012, 0.016, 0.012, 0.006)
				b.box("poly", Vector3(0, -0.06, 0.294), Vector3(0.04, 0.142, 0.008))
	b.cz("metal", -0.2, -0.216, BORE, 0.0235, 0.0235, 12)
	b.oct("furn", -0.214, -0.47, BORE, 0.021, 0.02, 0.009)
	for i in 5:
		var z := -0.25 - i * 0.048
		for sx in [-0.0212, 0.0212]:
			b.box("dark", Vector3(sx, BORE, z), Vector3(0.001, 0.007, 0.032))
		b.box("dark", Vector3(0, BORE - 0.0202, z), Vector3(0.007, 0.001, 0.032))
		for sx in [-1.0, 1.0]:
			b.box("dark", Vector3(sx * 0.0167, BORE + 0.0157, z), Vector3(0.006, 0.001, 0.03), Basis(Vector3.FORWARD, sx * -0.785))
	var ry := b.rail(0.02, -0.468, 0.0)
	var pts := [[-0.108, -0.07], [-0.162, -0.07], [-0.178, -0.16], [-0.198, -0.24], [-0.142, -0.25], [-0.126, -0.16]]
	var mk: String = att.get("mag", "std")
	if mk == "ext":
		pts = _scale_mag(pts, -0.07, 1.32)
	mb.ex("furn", pts, 0.0115)
	var last: Array = pts[4]
	var prev: Array = pts[3]
	mb.box("poly", Vector3(0, (last[1] + prev[1]) * 0.5 - 0.003, (last[0] + prev[0]) * 0.5), Vector3(0.027, 0.007, 0.062), Basis(Vector3.RIGHT, 0.17))
	if mk == "fast":
		mb.box("poly", Vector3(0, last[1] - 0.012, last[0] + 0.012), Vector3(0.012, 0.03, 0.03), Basis(Vector3.RIGHT, 0.5))
	return {"rail_y": ry, "optic_z": -0.07, "rear_z": 0.0, "rear_base": ry, "front_z": -0.44, "front_base": ry, "iron_axis": ry + 0.03,
		"hg_z": -0.47, "barrel_z": -0.6, "barrel_r": 0.0085, "std_muzzle": "flash", "fg_z": -0.36, "hg_bottom": -0.04,
		"hand_z": -0.37, "grip_z": 0.02, "hip": Vector3(0.1, -0.125, -0.33), "ads_z": -0.15, "rail_irons": true}


static func _akm(b: B, mb: B, att: Dictionary) -> Dictionary:
	b.oct("metal", 0.04, -0.2, -0.035, 0.0165, 0.027, 0.004)
	b.oct("metal", 0.036, -0.17, -0.003, 0.0155, 0.011, 0.008)
	for i in 6:
		b.box("metal", Vector3(0, 0.0085, 0.01 - i * 0.03), Vector3(0.022, 0.0015, 0.004))
	b.box("metal", Vector3(0, 0.002, -0.19), Vector3(0.026, 0.024, 0.042))
	b.cz("metal", -0.21, -0.4, 0.004, 0.0085, 0.0085, 10)
	b.oct("furn", -0.215, -0.335, 0.004, 0.016, 0.013, 0.006)
	b.oct("furn", -0.205, -0.375, -0.03, 0.02, 0.018, 0.007)
	for i in 3:
		for sx in [-0.0162, 0.0162]:
			b.box("dark", Vector3(sx, 0.006, -0.24 - i * 0.03), Vector3(0.001, 0.005, 0.016))
	b.box("metal", Vector3(0, -0.006, -0.412), Vector3(0.02, 0.036, 0.03))
	b.box("metal", Vector3(0, -0.02, -0.39), Vector3(0.024, 0.024, 0.012))
	_trigger(b, -0.045, -0.06)
	_grip(b, 0.012, -0.06)
	b.box("metal", Vector3(0.022, -0.012, -0.08), Vector3(0.014, 0.008, 0.012))
	b.box("dark", Vector3(0.0168, -0.014, -0.1), Vector3(0.001, 0.012, 0.07))
	b.box("metal", Vector3(0.0172, -0.04, -0.03), Vector3(0.002, 0.008, 0.09), Basis(Vector3.RIGHT, 0.08))
	b.box("metal", Vector3(0, -0.07, -0.078), Vector3(0.008, 0.024, 0.006), Basis(Vector3.RIGHT, 0.3))
	match att.get("stock", "std"):
		"light":
			b.box("metal", Vector3(0, -0.022, 0.165), Vector3(0.012, 0.012, 0.25), Basis(Vector3.RIGHT, -0.04))
			b.box("metal", Vector3(0, -0.08, 0.165), Vector3(0.01, 0.01, 0.26), Basis(Vector3.RIGHT, -0.3))
			b.box("poly", Vector3(0, -0.075, 0.292), Vector3(0.03, 0.115, 0.008))
		_:
			_stock_generic(b, att.get("stock", "std"), 0.04, -0.01, 0.25, 0.125)
	var ry := 0.008
	var optic: String = att.get("optic", "iron")
	if optic != "iron":
		ry = b.rail(0.02, -0.15, 0.008)
	_irons(b, -0.19, 0.012, -0.555, BORE, 0.034)
	var pts := [[-0.075, -0.062], [-0.14, -0.062], [-0.165, -0.13], [-0.205, -0.2], [-0.245, -0.245], [-0.2, -0.275], [-0.155, -0.225], [-0.115, -0.15], [-0.09, -0.1]]
	var mk: String = att.get("mag", "std")
	if mk == "ext":
		pts = _scale_mag(pts, -0.062, 1.25)
	mb.ex("poly", pts, 0.012)
	for i in 3:
		var p: Array = pts[2 + i]
		mb.box("metal", Vector3(0, p[1], p[0] + 0.022), Vector3(0.0255, 0.004, 0.05), Basis(Vector3.RIGHT, 0.45 + i * 0.12))
	if mk == "fast":
		mb.box("furn", Vector3(0, pts[5][1] + 0.0, pts[5][0] + 0.025), Vector3(0.012, 0.03, 0.03), Basis(Vector3.RIGHT, 0.9))
	return {"rail_y": ry, "optic_z": -0.065, "iron_axis": 0.034, "hg_z": -0.375, "barrel_z": -0.6, "barrel_r": 0.008,
		"std_muzzle": "comp", "fg_z": -0.3, "hg_bottom": -0.048, "hand_z": -0.3, "grip_z": 0.028,
		"hip": Vector3(0.1, -0.125, -0.33), "ads_z": -0.13, "rail_irons": false}


static func _smg(b: B, mb: B, att: Dictionary) -> Dictionary:
	b.oct("metal", 0.06, -0.2, -0.014, 0.019, 0.02, 0.008)
	b.ex("poly", [[0.05, -0.03], [-0.132, -0.03], [-0.134, -0.086], [-0.085, -0.086], [-0.085, -0.066], [-0.01, -0.066], [0.05, -0.05]], 0.0155)
	_trigger(b, -0.045, -0.064)
	_grip(b, 0.012, -0.062, "poly")
	b.oct("furn", -0.2, -0.335, -0.022, 0.02, 0.021, 0.008)
	for i in 3:
		for sx in [-0.0202, 0.0202]:
			b.box("dark", Vector3(sx, -0.022, -0.235 - i * 0.036), Vector3(0.001, 0.008, 0.024))
	b.cz("metal", -0.245, -0.258, -0.004, 0.006, 0.006, 8, -0.026)
	b.box("dark", Vector3(-0.0192, -0.004, -0.2), Vector3(0.001, 0.007, 0.12))
	b.box("dark", Vector3(0.0192, -0.016, -0.08), Vector3(0.001, 0.014, 0.05))
	b.box("metal", Vector3(-0.0165, -0.046, -0.01), Vector3(0.003, 0.006, 0.022))
	match att.get("stock", "std"):
		"heavy":
			_stock_generic(b, "std", 0.06, -0.004, 0.23, 0.12)
		"light":
			for sx in [-0.013, 0.013]:
				b.cz("metal", 0.17, 0.05, -0.02, 0.004, 0.004, 6, sx)
			b.box("poly", Vector3(0, -0.04, 0.174), Vector3(0.04, 0.07, 0.01))
		_:
			for sx in [-0.013, 0.013]:
				b.cz("metal", 0.26, 0.05, -0.02, 0.0045, 0.0045, 6, sx)
			b.box("poly", Vector3(0, -0.05, 0.266), Vector3(0.042, 0.1, 0.014))
			b.box("poly", Vector3(0, -0.02, 0.08), Vector3(0.036, 0.016, 0.03))
	var ry := b.rail(0.045, -0.33, 0.006)
	var pts := [[-0.088, -0.07], [-0.13, -0.07], [-0.152, -0.25], [-0.108, -0.255]]
	if att.get("mag", "std") == "ext":
		pts = _scale_mag(pts, -0.07, 1.35)
	mb.ex("metal", pts, 0.0095)
	mb.box("poly", Vector3(0, pts[2][1] - 0.004, (pts[2][0] + pts[3][0]) * 0.5), Vector3(0.023, 0.008, 0.05))
	if att.get("mag", "std") == "fast":
		mb.box("furn", Vector3(0, pts[2][1] - 0.02, pts[3][0] + 0.004), Vector3(0.012, 0.03, 0.026), Basis(Vector3.RIGHT, 0.5))
	return {"rail_y": ry, "optic_z": -0.05, "rear_z": 0.02, "rear_base": ry, "front_z": -0.3, "front_base": ry, "iron_axis": ry + 0.03,
		"hg_z": -0.335, "barrel_z": -0.4, "barrel_r": 0.008, "std_muzzle": "none", "fg_z": -0.275, "hg_bottom": -0.043,
		"hand_z": -0.275, "grip_z": 0.028, "hip": Vector3(0.095, -0.12, -0.3), "ads_z": -0.13, "rail_irons": true}


static func _lmg(b: B, mb: B, att: Dictionary) -> Dictionary:
	b.oct("metal", 0.07, -0.27, -0.03, 0.02, 0.03, 0.005)
	b.oct("metal", 0.05, -0.2, 0.007, 0.019, 0.007, 0.004)
	b.box("metal", Vector3(0, 0.004, -0.21), Vector3(0.03, 0.012, 0.02))
	var ry := b.rail(0.03, -0.18, 0.014)
	b.oct("furn", -0.27, -0.45, -0.03, 0.022, 0.021, 0.008)
	for i in 4:
		for sx in [-0.0222, 0.0222]:
			b.box("dark", Vector3(sx, -0.024, -0.3 - i * 0.04), Vector3(0.001, 0.01, 0.024))
	b.cz("metal", -0.45, -0.6, -0.046, 0.007, 0.007, 8)
	b.box("metal", Vector3(0, -0.034, -0.6), Vector3(0.022, 0.04, 0.03))
	b.box("metal", Vector3(0.014, 0.028, -0.3), Vector3(0.008, 0.05, 0.01), Basis(Vector3.FORWARD, -0.5))
	b.box("metal", Vector3(0.014, 0.028, -0.4), Vector3(0.008, 0.05, 0.01), Basis(Vector3.FORWARD, -0.5))
	b.cz("poly", -0.29, -0.41, 0.048, 0.008, 0.008, 8, 0.026)
	for sx in [-0.013, 0.013]:
		b.cz("metal", -0.47, -0.69, -0.058, 0.005, 0.005, 6, sx)
		b.box("metal", Vector3(sx, -0.058, -0.47), Vector3(0.012, 0.008, 0.014))
	b.box("metal", Vector3(0, -0.046, -0.685), Vector3(0.04, 0.02, 0.016))
	_trigger(b, -0.035, -0.058)
	_grip(b, 0.022, -0.058, "poly")
	b.box("metal", Vector3(0.024, -0.02, -0.12), Vector3(0.012, 0.008, 0.012))
	b.box("dark", Vector3(0.0202, -0.03, -0.14), Vector3(0.001, 0.014, 0.06))
	b.box("metal", Vector3(-0.028, -0.012, -0.11), Vector3(0.018, 0.012, 0.07))
	_stock_generic(b, att.get("stock", "std"), 0.07, -0.004, 0.24, 0.13)
	if att.get("optic", "iron") == "iron":
		_irons(b, 0.0, ry, -0.6, -0.014, ry + 0.03)
	var big: bool = att.get("mag", "std") == "ext"
	mb.box("furn", Vector3(-0.012, -0.118 - (0.014 if big else 0.0), -0.115), Vector3(0.088 if not big else 0.1, 0.108 + (0.028 if big else 0.0), 0.135))
	mb.box("poly", Vector3(-0.012, -0.063, -0.115), Vector3(0.092 if not big else 0.104, 0.006, 0.139))
	mb.box("metal", Vector3(-0.012, -0.118, -0.047), Vector3(0.03, 0.05, 0.003))
	for i in 5:
		mb.cz("brass", -0.085 - i * 0.012 + 0.005, -0.085 - i * 0.012 - 0.005, -0.03 + 0.0, 0.0045, 0.0045, 6, -0.03 - 0.004 * (i % 2))
	if att.get("mag", "std") == "fast":
		mb.box("poly", Vector3(-0.012, -0.176, -0.115), Vector3(0.03, 0.01, 0.06))
	return {"rail_y": ry, "optic_z": -0.07, "iron_axis": ry + 0.03, "hg_z": -0.45, "barrel_z": -0.7, "barrel_r": 0.011,
		"std_muzzle": "flash", "fg_z": -0.36, "hg_bottom": -0.051, "hand_z": -0.36, "grip_z": 0.038,
		"hip": Vector3(0.105, -0.135, -0.32), "ads_z": -0.15, "rail_irons": false, "laser_x": 0.031}


static func _dmr(b: B, mb: B, att: Dictionary) -> Dictionary:
	b.oct("metal", 0.04, -0.22, -0.028, 0.0165, 0.026, 0.005)
	b.oct("metal", 0.036, -0.2, 0.001, 0.014, 0.008, 0.006)
	var ry := b.rail(0.02, -0.2, 0.009)
	b.oct("furn", -0.22, -0.48, -0.022, 0.018, 0.02, 0.008)
	for i in 6:
		for sx in [-0.0182, 0.0182]:
			b.box("dark", Vector3(sx, -0.016, -0.25 - i * 0.038), Vector3(0.001, 0.006, 0.024), Basis(Vector3.RIGHT, 0.0))
	b.box("metal", Vector3(0, -0.012, -0.6), Vector3(0.018, 0.03, 0.026))
	_trigger(b, -0.04, -0.052)
	var sk: String = att.get("stock", "std")
	b.ex("furn", [[0.04, -0.008], [0.3, -0.014], [0.3, -0.04], [0.04, -0.044]], 0.014)
	b.ex("furn", [[-0.005, -0.05], [0.04, -0.044], [0.075, -0.044], [0.108, -0.16], [0.072, -0.166], [0.04, -0.09]], 0.0135)
	b.box("poly", Vector3(0, -0.075, 0.305), Vector3(0.032, 0.135, 0.012))
	if sk != "light":
		b.ex("furn", [[0.09, -0.15], [0.108, -0.16], [0.3, -0.13], [0.3, -0.108]], 0.011)
		b.oct("furn", 0.13, 0.26, 0.004, 0.014, 0.012, 0.006)
	if sk == "heavy":
		b.box("poly", Vector3(0, -0.075, 0.315), Vector3(0.038, 0.14, 0.01))
		b.oct("furn", 0.13, 0.26, 0.018, 0.013, 0.006, 0.004)
	b.box("metal", Vector3(0.021, -0.016, -0.09), Vector3(0.012, 0.008, 0.012))
	b.box("dark", Vector3(0.0168, -0.02, -0.11), Vector3(0.001, 0.014, 0.075))
	b.box("metal", Vector3(0.0172, -0.04, -0.02), Vector3(0.002, 0.007, 0.06))
	if att.get("optic", "iron") == "iron":
		_irons(b, 0.005, ry, -0.6, -0.002, ry + 0.028)
	var pts := [[-0.06, -0.054], [-0.135, -0.054], [-0.152, -0.15], [-0.078, -0.158]]
	if att.get("mag", "std") == "ext":
		pts = _scale_mag(pts, -0.054, 1.5)
	mb.ex("metal", pts, 0.012)
	for i in 3:
		mb.box("dark", Vector3(0.0122, lerpf(pts[0][1], pts[3][1], 0.25 + i * 0.25), -0.105 - i * 0.004), Vector3(0.001, 0.004, 0.06))
	if att.get("mag", "std") == "fast":
		mb.box("furn", Vector3(0, pts[2][1] - 0.012, pts[3][0] + 0.008), Vector3(0.012, 0.03, 0.03), Basis(Vector3.RIGHT, 0.4))
	return {"rail_y": ry, "optic_z": -0.08, "iron_axis": ry + 0.028, "hg_z": -0.48, "barrel_z": -0.74, "barrel_r": 0.0075,
		"std_muzzle": "flash", "fg_z": -0.38, "hg_bottom": -0.042, "hand_z": -0.37, "grip_z": 0.05,
		"hip": Vector3(0.1, -0.13, -0.35), "ads_z": -0.15, "rail_irons": false}


static func _sg(b: B, pump: B, att: Dictionary) -> Dictionary:
	b.oct("metal", 0.05, -0.2, -0.03, 0.017, 0.03, 0.006)
	var tube_end := -0.6 if att.get("mag", "std") == "ext" else -0.54
	b.cz("metal", -0.2, tube_end, -0.047, 0.0105, 0.0105, 10)
	b.cz("metal", tube_end, tube_end - 0.012, -0.047, 0.012, 0.012, 10)
	b.box("metal", Vector3(0, -0.034, -0.5), Vector3(0.012, 0.05, 0.016))
	pump.oct("furn", -0.27, -0.42, -0.047, 0.021, 0.019, 0.008)
	for i in 6:
		for sx in [-0.0212, 0.0212]:
			pump.box("dark", Vector3(sx, -0.047, -0.29 - i * 0.022), Vector3(0.001, 0.02, 0.008))
	pump.box("metal", Vector3(0.018, -0.03, -0.24), Vector3(0.004, 0.006, 0.07))
	_trigger(b, -0.03, -0.058)
	_grip(b, 0.026, -0.058, "poly")
	b.box("dark", Vector3(0.0172, -0.018, -0.1), Vector3(0.001, 0.016, 0.075))
	b.box("dark", Vector3(0, -0.0602, -0.13), Vector3(0.018, 0.001, 0.08))
	b.box("metal", Vector3(0.0, -0.064, 0.012), Vector3(0.012, 0.006, 0.012))
	_stock_generic(b, att.get("stock", "std"), 0.05, -0.006, 0.26, 0.13)
	var ry := 0.0
	if att.get("optic", "iron") != "iron":
		ry = b.rail(0.03, -0.17, 0.0)
	else:
		_irons(b, 0.0, 0.0, -0.57, -0.009, 0.024)
	return {"rail_y": ry, "optic_z": -0.07, "iron_axis": 0.024, "hg_z": -0.2, "barrel_z": -0.6, "barrel_r": 0.0105,
		"std_muzzle": "none", "fg_z": -0.345, "hg_bottom": -0.066, "hand_z": -0.345, "grip_z": 0.042,
		"hip": Vector3(0.1, -0.13, -0.33), "ads_z": -0.14, "rail_irons": false, "laser_x": 0.0, "laser_y": -0.064, "laser_z": -0.47}


## Собирает модель оружия. arms = false — без рук (для витрины в оружейной).
static func build(id: String, att: Dictionary, arms := true) -> Dictionary:
	if GunAssets.has(id) and not "--oldguns" in OS.get_cmdline_user_args():
		return GunAssets.build(id, att, arms)
	if id == "sr":
		return build_sniper(att, arms)
	if id == "pistol":
		return build_pistol(att, arms)
	var root := Node3D.new()
	var mats := _mats(att.get("camo", "black"))
	var b := B.new()
	var mb := B.new()
	var pb := B.new()
	var g := {}
	match id:
		"akm":
			g = _akm(b, mb, att)
		"smg":
			g = _smg(b, mb, att)
		"lmg":
			g = _lmg(b, mb, att)
		"dmr":
			g = _dmr(b, mb, att)
		"sg":
			g = _sg(b, pb, att)
		_:
			g = _ar(b, mb, att)
	var bz: float = float(g.barrel_z) + float({"long": -0.07, "short": 0.07}.get(att.get("barrel", "std"), 0.0))
	b.cz("metal", float(g.hg_z) + 0.01, bz, BORE, float(g.barrel_r), float(g.barrel_r), 10)
	var mk: String = att.get("muzzle", "none")
	var muzzle_z := _muzzle(b, mk if mk != "none" else String(g.std_muzzle), bz, float(g.barrel_r))
	var optic: String = att.get("optic", "iron")
	var glass: Array = []
	var sight_y: float = g.iron_axis
	if optic == "iron":
		if g.rail_irons:
			_irons(b, g.rear_z, g.rear_base, g.front_z, g.front_base, g.iron_axis)
	else:
		sight_y = _optic(b, glass, optic, float(g.rail_y), float(g.optic_z))
	var fg: String = att.get("grip", "none")
	_foregrip(b, fg, float(g.fg_z), float(g.hg_bottom))
	if att.get("laser", "none") == "laser":
		_laser(b, float(g.get("laser_z", float(g.fg_z) - 0.07)), float(g.get("laser_x", 0.03)), float(g.get("laser_y", BORE + 0.004)))
	b.commit(root, mats)
	for gl in glass:
		var q := QuadMesh.new()
		q.size = gl[1]
		_add(root, q, mats.glass, Transform3D(Basis(), gl[0]))
	var mag: Node3D = null
	if not mb.st.is_empty():
		mag = Node3D.new()
		root.add_child(mag)
		mb.commit(mag, mats)
	var pump: Node3D = null
	if not pb.st.is_empty():
		pump = Node3D.new()
		root.add_child(pump)
		pb.commit(pump, mats)
	if arms:
		var gz: float = g.grip_z
		_arm(root, Vector3(0.17, -0.27, gz + 0.27), Vector3(0.016, -0.15, gz + 0.045), Vector3(0.003, -0.118, gz + 0.012), 0)
		var hz: float = g.hand_z
		var hb: float = g.hg_bottom
		var lhost: Node3D = pump if pump else root
		if fg == "vert":
			_arm(lhost, Vector3(-0.2, -0.32, hz + 0.26), Vector3(-0.03, -0.13, hz + 0.05), Vector3(0.0, hb - 0.052, hz + 0.004), 2, true)
		else:
			_arm(lhost, Vector3(-0.2, -0.3, hz + 0.27), Vector3(-0.034, hb - 0.05, hz + 0.055), Vector3(-0.004, hb - 0.03, hz), 1, true)
	return {"root": root, "mag": mag, "pump": pump, "muzzle": Vector3(0, BORE, muzzle_z), "hip": g.hip,
		"ads": Vector3(0.0, -sight_y, float(g.ads_z)), "parts": [], "length": absf(muzzle_z) + 0.3}


static func build_sniper(att: Dictionary, arms := true) -> Dictionary:
	var root := Node3D.new()
	var model: Node3D = (load("res://assets/models/bolt_action_rifle_7_62/bolt_action_rifle_7_62.gltf") as PackedScene).instantiate()
	Mats.register_scene(model)
	model.rotation.y = PI * 0.5
	root.add_child(model)
	_apply_vm(model)
	var parts: Array = []
	for c in model.get_children():
		var n := String(c.name)
		if n.contains("bullet"):
			(c as Node3D).visible = false
		elif n.contains("bolt"):
			parts.append([c, (c as Node3D).position])
	var muzzle := Vector3(0, 0.03, -0.62)
	if att.get("muzzle", "none") == "supp":
		var b := B.new()
		muzzle.z = _muzzle(b, "supp", -0.62, 0.008, 0.03)
		b.commit(root, _mats("black"))
	if arms:
		_arm(root, Vector3(0.2, -0.3, 0.62), Vector3(0.022, -0.085, 0.365), Vector3(0.006, -0.052, 0.325), 0)
		_arm(root, Vector3(-0.22, -0.32, 0.22), Vector3(-0.034, -0.1, 0.0), Vector3(-0.004, -0.062, -0.06), 1, true)
	return {"root": root, "mag": null, "pump": null, "muzzle": muzzle, "hip": Vector3(0.095, -0.13, -0.44),
		"ads": Vector3(0.0, -0.095, -0.4), "parts": parts, "length": 1.25, "center_z": 0.0}


static func build_pistol(att: Dictionary, arms := true) -> Dictionary:
	var root := Node3D.new()
	var model: Node3D = (load("res://assets/models/service_pistol/service_pistol.gltf") as PackedScene).instantiate()
	Mats.register_scene(model)
	model.rotation.y = PI * 0.5
	root.add_child(model)
	_apply_vm(model)
	var parts: Array = []
	for c in model.get_children():
		var n := String(c.name)
		if n.contains("magazine") or n.contains("bullet") or n.ends_with("_b"):
			(c as Node3D).visible = false
		elif n.contains("slide"):
			parts.append([c, (c as Node3D).position])
	var muzzle := Vector3(0, 0.06, -0.19)
	var b := B.new()
	if att.get("muzzle", "none") == "supp":
		muzzle.z = _muzzle(b, "supp", -0.2, 0.007, 0.06) + 0.03
	if att.get("laser", "none") == "laser":
		_laser(b, -0.13, 0.0, 0.028)
	if att.get("mag", "std") == "ext":
		b.box("metal", Vector3(0, -0.075, 0.035), Vector3(0.022, 0.03, 0.036), Basis(Vector3.RIGHT, -0.2))
	if not b.st.is_empty():
		b.commit(root, _mats("black"))
	if arms:
		_arm(root, Vector3(0.14, -0.25, 0.33), Vector3(0.014, -0.1, 0.085), Vector3(0.002, -0.035, 0.03), 0, false, 0.7)
		# левая кисть обхватывает правую снизу-спереди
		_arm(root, Vector3(-0.2, -0.28, 0.27), Vector3(-0.05, -0.115, 0.07), Vector3(-0.022, -0.055, 0.02), 0, true, 0.7)
	return {"root": root, "mag": null, "pump": null, "muzzle": muzzle, "hip": Vector3(0.07, -0.1, -0.36),
		"ads": Vector3(0.0, -0.083, -0.37), "parts": parts, "length": 0.42, "center_z": -0.04}
