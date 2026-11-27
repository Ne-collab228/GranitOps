extends SceneTree
## Склейка моделей машин из assets/vehicles/src (FBX) в assets/vehicles/<id>.res (VehicleModel).
## Запуск: G --headless --path . --script res://tools/flatten_vehicles.gd
## Плоские материалы исходника превращаются в цвет вершин (кузов — 1–2 поверхности вместо 6–10),
## окраска перекрашивается в варианты VehDefs.DEFS[id].colors, колесо — отдельный меш.

const DETAIL := "res://assets/guns/detail_alb.png"
const DETAIL_R := "res://assets/guns/detail_rough.png"

var _mats := {}


func _init() -> void:
	for id in VehDefs.DEFS:
		_flatten(id, VehDefs.DEFS[id])
	for id in VehDefs.WRECKS:
		_wreck(id, VehDefs.WRECKS[id])
	quit()


## Материал машины: цвет вершин × (текстура исходника или общая «грязь» трипланаром).
func _material(tex_path: String, glass := false) -> StandardMaterial3D:
	var key := tex_path + ("|g" if glass else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if tex_path != "":
		m.albedo_texture = load(tex_path)
		m.roughness = 0.7
	else:
		m.albedo_texture = load(DETAIL)
		m.roughness_texture = load(DETAIL_R)
		m.roughness = 0.75
		m.metallic = 0.25
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_scale = Vector3.ONE * 0.8
	_mats[key] = m
	return m


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, t])
	for c in n.get_children():
		_collect(c, t, out)


func _mat_info(mi: MeshInstance3D, s: int) -> Dictionary:
	var mat: Material = mi.get_surface_override_material(s)
	if mat == null:
		mat = mi.mesh.surface_get_material(s)
	var info := {"name": "", "color": Color.WHITE, "tex": ""}
	if mat:
		info.name = mat.resource_name
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			info.color = bm.albedo_color
			if bm.albedo_texture and bm.albedo_texture.resource_path != "" and not bm.albedo_texture.resource_path.contains("::"):
				info.tex = bm.albedo_texture.resource_path
			elif bm.albedo_texture:
				# встроенная в FBX текстура — сохранить рядом
				var p := "res://assets/vehicles/tex_%s.png" % String(info.name).validate_filename()
				if not FileAccess.file_exists(p):
					bm.albedo_texture.get_image().save_png(p)
				info.tex = p
	return info


## Добавляет поверхности mi (с преобразованием xf и масштабом) в группы по текстуре.
## groups: tex -> [verts, normals, uvs, colors, indices]
func _append(groups: Dictionary, mi: MeshInstance3D, xf: Transform3D, def: Dictionary, paint: Color) -> void:
	var nb := xf.basis.inverse().transposed()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var info := _mat_info(mi, s)
		var col: Color = info.color
		var glass := false
		if (def.paint as Array).has(info.name):
			col = paint
		elif (def.glass as Array).has(info.name):
			col = Color(0.12, 0.15, 0.17)
			glass = true
		elif String(info.name).begins_with("glow") or info.name == "headlights":
			col = Color(0.85, 0.82, 0.7)
		elif info.name == "rear lights":
			col = Color(0.5, 0.06, 0.05)
		var key: String = info.tex
		if not groups.has(key):
			groups[key] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
		var g: Array = groups[key]
		var gv: PackedVector3Array = g[0]
		var gn: PackedVector3Array = g[1]
		var gu: PackedVector2Array = g[2]
		var gc: PackedColorArray = g[3]
		var gi: PackedInt32Array = g[4]
		var base := gv.size()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		for i in verts.size():
			gv.append(xf * verts[i])
			gn.append((nb * norms[i]).normalized() if not norms.is_empty() else Vector3.UP)
			gu.append(uvs[i] if not uvs.is_empty() else Vector2.ZERO)
			# стёкла чуть темнее и «глянцевее» не сделать без отдельного материала — только цвет
			gc.append(col if not glass else col)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i in verts.size():
				gi.append(base + i)
		else:
			for i in idx:
				gi.append(base + i)
		groups[key] = [gv, gn, gu, gc, gi]


func _build_mesh(groups: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in groups:
		var g: Array = groups[key]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = g[0]
		a[Mesh.ARRAY_NORMAL] = g[1]
		a[Mesh.ARRAY_TEX_UV] = g[2]
		a[Mesh.ARRAY_COLOR] = g[3]
		a[Mesh.ARRAY_INDEX] = g[4]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key))
	return mesh


func _flatten(id: String, def: Dictionary) -> void:
	var ps: PackedScene = load("res://assets/vehicles/src/" + String(def.src))
	var root := ps.instantiate()
	var items: Array = []
	_collect(root, Transform3D(), items)
	var rot := Basis(Vector3.UP, PI) if bool(def.flip) else Basis()
	var ws: float = def.ws
	var bs := Vector3(ws * float(def.sx), ws, ws * float(def.sz))
	var skip: Array = def.get("skip", [])
	var body_items: Array = []
	var wheel_items: Array = []
	for it in items:
		var mi: MeshInstance3D = it[0]
		if skip.has(String(mi.name)):
			continue
		if String(mi.name).to_lower().contains("wheel"):
			wheel_items.append(it)
		else:
			body_items.append(it)
	# ступицы в «повёрнутых» координатах до масштаба
	var raw_hubs: Array = []
	var r_raw := 0.0
	for it in wheel_items:
		var mi: MeshInstance3D = it[0]
		var t: Transform3D = Transform3D(rot) * (it[1] as Transform3D)
		var bb: AABB = t * mi.mesh.get_aabb()
		raw_hubs.append(bb.get_center())
		r_raw = maxf(r_raw, bb.size.y * 0.5)
	var r := r_raw * ws
	# сдвиг: низ колёс на y=0, центр кузова по X/Z в 0
	var bmin := Vector3.INF
	var bmax := -Vector3.INF
	for it in body_items:
		var mi: MeshInstance3D = it[0]
		var t: Transform3D = Transform3D(rot) * (it[1] as Transform3D)
		var bb: AABB = t * mi.mesh.get_aabb()
		bmin = bmin.min(bb.position * bs)
		bmax = bmax.max(bb.end * bs)
	var hub_y := 0.0
	for h in raw_hubs:
		hub_y += (h as Vector3).y * ws
	hub_y /= maxf(1.0, raw_hubs.size())
	var shift := Vector3(-(bmin.x + bmax.x) * 0.5, -(hub_y - r), -(bmin.z + bmax.z) * 0.5)
	var hubs: Array = []
	for h in raw_hubs:
		var hp: Vector3 = (h as Vector3) * bs + shift
		hp.y = r
		hubs.append(hp)
	hubs.sort_custom(func(a, b): return a.z < b.z - 0.1 or (absf(a.z - b.z) <= 0.1 and a.x < b.x))
	var vm := VehicleModel.new()
	vm.wheel_r = r
	vm.hubs = PackedVector3Array(hubs)
	vm.body_aabb = AABB(bmin + shift, bmax - bmin)
	# колесо: правое (x > 0), вокруг своей ступицы, равномерный масштаб ws
	var wheel_groups := {}
	for k in wheel_items.size():
		var it: Array = wheel_items[k]
		var hub_final: Vector3 = (raw_hubs[k] as Vector3) * bs + shift
		if hub_final.x <= 0.0:
			continue
		var t: Transform3D = Transform3D(rot) * (it[1] as Transform3D)
		var wt := Transform3D(Basis.from_scale(Vector3.ONE * ws), -(raw_hubs[k] as Vector3) * ws) * t
		_append(wheel_groups, it[0], wt, def, Color.WHITE)
		break
	vm.wheel = _build_mesh(wheel_groups)
	for c in (def.colors as Array):
		var groups := {}
		var far := {}
		for it in body_items:
			var t: Transform3D = Transform3D(Basis.from_scale(bs), shift) * Transform3D(rot) * (it[1] as Transform3D)
			_append(groups, it[0], t, def, c)
			_append(far, it[0], t, def, c)
		# дальний вариант: колёса впаяны в кузов
		for k in vm.hubs.size():
			var hp: Vector3 = vm.hubs[k]
			var src_k := -1
			for j in wheel_items.size():
				var hf: Vector3 = (raw_hubs[j] as Vector3) * bs + shift
				if hf.x > 0.0:
					src_k = j
					break
			if src_k < 0:
				break
			var it2: Array = wheel_items[src_k]
			var t2: Transform3D = Transform3D(rot) * (it2[1] as Transform3D)
			var local := Transform3D(Basis.from_scale(Vector3.ONE * ws), -(raw_hubs[src_k] as Vector3) * ws) * t2
			var place := Transform3D(Basis(Vector3.UP, PI) if hp.x < 0.0 else Basis(), hp)
			_append(far, it2[0], place * local, def, c)
		vm.bodies.append(_build_mesh(groups))
		vm.bodies_far.append(_build_mesh(far))
	var path := "res://assets/vehicles/%s.res" % id
	var err := ResourceSaver.save(vm, path, ResourceSaver.FLAG_COMPRESS)
	var tris := 0
	for s in vm.bodies[0].get_surface_count():
		tris += (vm.bodies[0].surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("%s: кузов %d тр., поверхностей %d, колёс %d, r=%.2f, габариты %s, ошибка %d" % [id, tris, vm.bodies[0].get_surface_count(), vm.hubs.size(), r, vm.body_aabb.size, err])
	root.free()


func _wreck(id: String, def: Dictionary) -> void:
	var ps: PackedScene = load("res://assets/vehicles/src/" + String(def.src))
	var root := ps.instantiate()
	var items: Array = []
	_collect(root, Transform3D(), items)
	var bmin := Vector3.INF
	var bmax := -Vector3.INF
	for it in items:
		var bb: AABB = (it[1] as Transform3D) * (it[0] as MeshInstance3D).mesh.get_aabb()
		bmin = bmin.min(bb.position)
		bmax = bmax.max(bb.end)
	var k: float = float(def.len) / maxf(bmax.z - bmin.z, bmax.x - bmin.x)
	var shift := Vector3(-(bmin.x + bmax.x) * 0.5, -bmin.y, -(bmin.z + bmax.z) * 0.5) * k
	var groups := {}
	var plain := {"paint": [], "glass": []}
	for it in items:
		_append(groups, it[0], Transform3D(Basis.from_scale(Vector3.ONE * k), shift) * (it[1] as Transform3D), plain, Color.WHITE)
	var mesh := _build_mesh(groups)
	ResourceSaver.save(mesh, "res://assets/vehicles/%s.res" % id, ResourceSaver.FLAG_COMPRESS)
	print("%s: остов, масштаб %.3f, габариты %s" % [id, k, (bmax - bmin) * k])
	root.free()
