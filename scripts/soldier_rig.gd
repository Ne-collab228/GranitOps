class_name SoldierRig
extends RefCounted
## Процедурный солдат: один скиннутый меш (1 draw call) + скелет из 13 костей.

enum B { HIPS, SPINE, CHEST, HEAD, L_ARM, L_FORE, R_ARM, R_FORE, L_THIGH, L_SHIN, R_THIGH, R_SHIN, GUN }

const BONES := [
	["hips", -1, Vector3(0, 0.95, 0)],
	["spine", 0, Vector3(0, 0.12, 0)],
	["chest", 1, Vector3(0, 0.22, 0)],
	["head", 2, Vector3(0, 0.30, 0)],
	["l_arm", 2, Vector3(-0.21, 0.22, 0)],
	["l_fore", 4, Vector3(0, -0.28, 0)],
	["r_arm", 2, Vector3(0.21, 0.22, 0)],
	["r_fore", 6, Vector3(0, -0.28, 0)],
	["l_thigh", 0, Vector3(-0.10, -0.04, 0)],
	["l_shin", 8, Vector3(0, -0.44, 0)],
	["r_thigh", 0, Vector3(0.10, -0.04, 0)],
	["r_shin", 10, Vector3(0, -0.44, 0)],
	["gun", 2, Vector3(0.13, 0.13, -0.2)],
]
const MUZZLE := Vector3(0, 0.012, -0.6)
const ARM_L1 := 0.28
const ARM_L2 := 0.31

static var _meshes := {}
static var _skin: Skin
static var _lod := 0

static var _v := PackedVector3Array()
static var _n := PackedVector3Array()
static var _uv := PackedVector2Array()
static var _bones := PackedInt32Array()
static var _w := PackedFloat32Array()
static var _idx := PackedInt32Array()


static func _global_rest(bone: int) -> Vector3:
	var p := Vector3.ZERO
	var b := bone
	while b >= 0:
		p += BONES[b][2]
		b = BONES[b][1]
	return p


## tile - ячейка атласа 4x2: 0 камуфляж, 1 разгрузка, 2 кожа, 3 чёрное, 4 шлем, 5 металл, 6 дерево, 7 стропы.
## detail = true - деталь только для ближней модели.
static func _add(prim: PrimitiveMesh, bone: int, offset: Vector3, tile: int, rot := Basis(), scale := Vector3.ONE, detail := false) -> void:
	if detail and _lod > 0:
		return
	var a := prim.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var xf := Transform3D(rot.scaled(scale), _global_rest(bone) + offset)
	var inv := Vector3(1.0 / scale.x, 1.0 / scale.y, 1.0 / scale.z)
	var base := _v.size()
	var col := tile % 4
	var row := tile / 4
	for i in v.size():
		_v.append(xf * v[i])
		_n.append((rot * (n[i] * inv)).normalized())
		_uv.append(Vector2((col + 0.05 + fposmod(uv[i].x, 1.0) * 0.9) * 0.25, (row + 0.05 + fposmod(uv[i].y, 1.0) * 0.9) * 0.5))
		_bones.append(bone)
		_bones.append(0)
		_bones.append(0)
		_bones.append(0)
		_w.append(1.0)
		_w.append(0.0)
		_w.append(0.0)
		_w.append(0.0)
	for i in idx:
		_idx.append(base + i)


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _caps(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 2
	return m


static func _sph(r: float, h: float, hemi := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 5
	m.is_hemisphere = hemi
	return m


static func _cylm(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


## kind: 0 - стрелок, 1 - штурмовик в тяжёлой броне, 2 - снайпер. lod: 0 - подробная, 1 - упрощённая (вдали).
static func mesh(kind := 0, lod := 0) -> ArrayMesh:
	var key := kind * 2 + lod
	if _meshes.has(key):
		return _meshes[key]
	_lod = lod
	_v.clear()
	_n.clear()
	_uv.clear()
	_bones.clear()
	_w.clear()
	_idx.clear()
	var zrot := Basis(Vector3.RIGHT, PI * 0.5)
	var one := Vector3.ONE
	var id := Basis()
	# --- таз и живот
	_add(_sph(0.175, 0.27), B.HIPS, Vector3(0, 0.0, 0), 0, id, Vector3(1, 1, 0.74))
	_add(_box(Vector3(0.36, 0.05, 0.25)), B.HIPS, Vector3(0, 0.1, 0), 7, id, one, true)
	_add(_box(Vector3(0.09, 0.09, 0.06)), B.HIPS, Vector3(-0.15, 0.06, 0.08), 7, id, one, true)
	_add(_box(Vector3(0.1, 0.07, 0.07)), B.HIPS, Vector3(0.0, 0.05, 0.15), 7, id, one, true)
	_add(_box(Vector3(0.31, 0.25, 0.2)), B.SPINE, Vector3(0, 0.11, 0), 0)
	# --- грудь, бронежилет, подсумки
	_add(_box(Vector3(0.4, 0.3, 0.24)), B.CHEST, Vector3(0, 0.13, 0), 0)
	_add(_box(Vector3(0.33, 0.35, 0.07)), B.CHEST, Vector3(0, 0.09, -0.135), 1)
	_add(_box(Vector3(0.33, 0.35, 0.07)), B.CHEST, Vector3(0, 0.09, 0.135), 1)
	_add(_box(Vector3(0.43, 0.15, 0.22)), B.CHEST, Vector3(0, -0.02, 0), 1, id, one, true)
	for px in [-0.105, 0.0, 0.105]:
		_add(_box(Vector3(0.09, 0.135, 0.055)), B.CHEST, Vector3(px, -0.02, -0.195), 7, id, one, true)
		_add(_box(Vector3(0.092, 0.03, 0.058)), B.CHEST, Vector3(px, 0.055, -0.196), 3, id, one, true)
	_add(_box(Vector3(0.07, 0.12, 0.05)), B.CHEST, Vector3(-0.12, 0.17, -0.185), 3, id, one, true)
	_add(_cylm(0.008, 0.2), B.CHEST, Vector3(-0.12, 0.31, -0.17), 3, id, one, true)
	for sx in [-0.1, 0.1]:
		_add(_box(Vector3(0.065, 0.035, 0.27)), B.CHEST, Vector3(sx, 0.285, 0), 1, id, one, true)
	_add(_cylm(0.08, 0.07), B.CHEST, Vector3(0, 0.29, 0), 0)
	for sx in [-0.21, 0.21]:
		_add(_sph(0.09, 0.18), B.CHEST, Vector3(sx, 0.235, 0), 0)
	if kind != 2:
		_add(_box(Vector3(0.27, 0.32, 0.13)), B.CHEST, Vector3(0, 0.1, 0.225), 7)
		_add(_box(Vector3(0.2, 0.12, 0.05)), B.CHEST, Vector3(0, 0.03, 0.305), 7, id, one, true)
		_add(_cylm(0.035, 0.26), B.CHEST, Vector3(0, 0.28, 0.24), 0, Basis(Vector3.FORWARD, PI * 0.5), one, true)
	if kind == 1:
		for sx in [-0.26, 0.26]:
			_add(_box(Vector3(0.12, 0.15, 0.17)), B.CHEST, Vector3(sx, 0.2, 0), 1)
		_add(_box(Vector3(0.21, 0.19, 0.05)), B.HIPS, Vector3(0, -0.09, -0.125), 1)
		_add(_box(Vector3(0.2, 0.09, 0.05)), B.CHEST, Vector3(0, 0.3, -0.12), 1)
		for sx in [-0.167, 0.167]:
			_add(_box(Vector3(0.05, 0.2, 0.14)), B.HIPS, Vector3(sx, -0.1, 0), 1, id, one, true)
	# --- голова
	_add(_cylm(0.056, 0.1), B.HEAD, Vector3(0, 0.03, 0), 2)
	_add(_sph(0.1, 0.235), B.HEAD, Vector3(0, 0.15, 0), 2)
	_add(_box(Vector3(0.035, 0.04, 0.04)), B.HEAD, Vector3(0, 0.125, -0.1), 2, id, one, true)
	if kind == 2:
		_add(_cylm(0.175, 0.012), B.HEAD, Vector3(0, 0.215, 0), 4)
		_add(_cylm(0.108, 0.085), B.HEAD, Vector3(0, 0.255, 0), 4)
		_add(_cylm(0.092, 0.08), B.HEAD, Vector3(0, 0.04, 0), 7)
		_add(_box(Vector3(0.36, 0.34, 0.05)), B.CHEST, Vector3(0, 0.1, 0.18), 4)
	else:
		_add(_sph(0.132, 0.135, true), B.HEAD, Vector3(0, 0.168, 0.008), 4)
		_add(_cylm(0.135, 0.022), B.HEAD, Vector3(0, 0.17, 0.008), 4, id, one, true)
		for sx in [-0.118, 0.118]:
			_add(_box(Vector3(0.035, 0.075, 0.065)), B.HEAD, Vector3(sx, 0.135, 0.012), 3, id, one, true)
		_add(_box(Vector3(0.16, 0.045, 0.035)), B.HEAD, Vector3(0, 0.215, -0.108), 3, Basis(Vector3.RIGHT, 0.3), one, true)
		_add(_box(Vector3(0.045, 0.04, 0.03)), B.HEAD, Vector3(0, 0.25, -0.118), 3, id, one, true)
	if kind == 1:
		_add(_box(Vector3(0.17, 0.11, 0.11)), B.HEAD, Vector3(0, 0.1, -0.045), 3)
	else:
		_add(_box(Vector3(0.172, 0.045, 0.03)), B.HEAD, Vector3(0, 0.155, -0.094), 3)
		_add(_box(Vector3(0.15, 0.07, 0.09)), B.HEAD, Vector3(0, 0.08, -0.04), 7 if kind == 2 else 0, id, one, true)
	# --- руки
	for b in [B.L_ARM, B.R_ARM]:
		_add(_caps(0.058, 0.34), b, Vector3(0, -0.14, 0), 0)
		_add(_box(Vector3(0.05, 0.1, 0.09)), b, Vector3(-0.045 if b == B.L_ARM else 0.045, -0.1, 0), 7, id, one, true)
	for b in [B.L_FORE, B.R_FORE]:
		_add(_sph(0.056, 0.112), b, Vector3(0, 0, 0), 0, id, one, true)
		_add(_caps(0.048, 0.3), b, Vector3(0, -0.13, 0), 0)
		_add(_box(Vector3(0.085, 0.09, 0.05)), b, Vector3(0, -0.02, 0.045), 1, id, one, true)
		_add(_cylm(0.05, 0.03), b, Vector3(0, -0.255, 0), 3, id, one, true)
		_add(_box(Vector3(0.075, 0.1, 0.085)), b, Vector3(0, -0.31, 0), 3)
	# --- ноги
	for b in [B.L_THIGH, B.R_THIGH]:
		var side := -1.0 if b == B.L_THIGH else 1.0
		_add(_caps(0.09, 0.5), b, Vector3(0, -0.22, 0), 0)
		_add(_box(Vector3(0.045, 0.14, 0.12)), b, Vector3(side * 0.085, -0.2, 0), 0, id, one, true)
		if b == B.R_THIGH:
			_add(_box(Vector3(0.05, 0.15, 0.09)), b, Vector3(0.105, -0.08, 0.01), 3, id, one, true)
	for b in [B.L_SHIN, B.R_SHIN]:
		_add(_sph(0.072, 0.144), b, Vector3(0, 0, 0), 0, id, one, true)
		_add(_caps(0.066, 0.46), b, Vector3(0, -0.21, 0), 0)
		_add(_box(Vector3(0.115, 0.13, 0.05)), b, Vector3(0, -0.02, -0.072), 1)
		_add(_box(Vector3(0.112, 0.15, 0.15)), b, Vector3(0, -0.405, 0.0), 3)
		_add(_box(Vector3(0.106, 0.085, 0.16)), b, Vector3(0, -0.45, -0.12), 3)
		_add(_box(Vector3(0.118, 0.025, 0.31)), b, Vector3(0, -0.495, -0.05), 3, id, one, true)
	# --- оружие
	_add(_box(Vector3(0.045, 0.07, 0.3)), B.GUN, Vector3(0, 0, -0.03), 5)
	_add(_box(Vector3(0.038, 0.022, 0.24)), B.GUN, Vector3(0, 0.044, -0.03), 5, id, one, true)
	_add(_box(Vector3(0.048, 0.058, 0.2)), B.GUN, Vector3(0, 0.0, -0.28), 6)
	_add(_cylm(0.009, 0.2), B.GUN, Vector3(0, 0.036, -0.3), 5, zrot, one, true)
	_add(_box(Vector3(0.04, 0.085, 0.24)), B.GUN, Vector3(0, -0.022, 0.24), 6, Basis(Vector3.RIGHT, -0.08))
	_add(_box(Vector3(0.03, 0.1, 0.045)), B.GUN, Vector3(0, -0.075, 0.07), 3, Basis(Vector3.RIGHT, -0.3))
	if kind == 2:
		_add(_cylm(0.011, 0.5), B.GUN, Vector3(0, 0.012, -0.5), 5, zrot)
		_add(_cylm(0.021, 0.24), B.GUN, Vector3(0, 0.082, -0.05), 3, zrot)
		_add(_cylm(0.027, 0.06), B.GUN, Vector3(0, 0.082, -0.19), 3, zrot, one, true)
		_add(_box(Vector3(0.028, 0.09, 0.06)), B.GUN, Vector3(0, -0.07, -0.08), 5)
	else:
		_add(_cylm(0.011, 0.3), B.GUN, Vector3(0, 0.012, -0.47), 5, zrot)
		_add(_box(Vector3(0.012, 0.05, 0.014)), B.GUN, Vector3(0, 0.036, -0.585), 5, id, one, true)
		_add(_cylm(0.016, 0.04), B.GUN, Vector3(0, 0.012, -0.61), 5, zrot, one, true)
		_add(_box(Vector3(0.028, 0.11, 0.06)), B.GUN, Vector3(0, -0.08, -0.08), 5, Basis(Vector3.RIGHT, 0.2))
		_add(_box(Vector3(0.028, 0.1, 0.058)), B.GUN, Vector3(0, -0.165, -0.118), 5, Basis(Vector3.RIGHT, 0.55))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_BONES] = _bones
	arrays[Mesh.ARRAY_WEIGHTS] = _w
	arrays[Mesh.ARRAY_INDEX] = _idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = m
	return m


static func make_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	for b in BONES:
		sk.add_bone(b[0])
	for i in BONES.size():
		if BONES[i][1] >= 0:
			sk.set_bone_parent(i, BONES[i][1])
		sk.set_bone_rest(i, Transform3D(Basis(), BONES[i][2]))
		sk.set_bone_pose_position(i, BONES[i][2])
	return sk


static func skin(sk: Skeleton3D) -> Skin:
	if _skin == null:
		_skin = sk.create_skin_from_rest_transforms()
	return _skin


## Двухзвенная ИК руки в пространстве кости груди: плечо s -> кисть t, локоть тянется к pole.
static func arm_ik(sk: Skeleton3D, upper: int, fore: int, s: Vector3, t: Vector3, pole: Vector3) -> void:
	var to := t - s
	var d := clampf(to.length(), 0.05, (ARM_L1 + ARM_L2) * 0.995)
	var dir := to.normalized()
	var a := (ARM_L1 * ARM_L1 - ARM_L2 * ARM_L2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, ARM_L1 * ARM_L1 - a * a))
	var pp := pole - dir * pole.dot(dir)
	if pp.length() < 0.001:
		pp = Vector3.DOWN
	pp = pp.normalized()
	var e := s + dir * a + pp * h
	var uq := Quaternion(Vector3.DOWN, (e - s).normalized())
	var fdir := (uq.inverse() * (s + dir * d - e)).normalized()
	sk.set_bone_pose_rotation(upper, uq)
	sk.set_bone_pose_rotation(fore, Quaternion(Vector3.DOWN, fdir))
