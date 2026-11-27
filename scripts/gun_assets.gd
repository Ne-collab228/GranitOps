class_name GunAssets
extends RefCounted
## Модели оружия из готовых CC0-моделей (assets/guns, см. tools/import_guns.py) вместо процедурных.
##
## * ar — M4A1 (nisu), akm — АКМ (LonesomeDucky): PBR-текстуры 1K.
## * smg, lmg, dmr, sg — стилизованные модели Pichuliru: свои материалы (металл/полимер) с трипланарной
##   детализацией (царапины, зерно, пятна), чтобы плоские заливки выглядели как настоящая отделка.
## * обвес (прицелы, глушитель, рукоятки, ЛЦУ) — Pichuliru Flat Attachments с теми же материалами.
##
## Геометрия разбивается на части (корпус, магазин, затвор, помпа, механический прицел), внутри части —
## по одной поверхности на материал: 4–7 вызовов отрисовки на ствол вместо ~22 у процедурного.
## Система координат та же, что в GunModels: ствол в -Z, ось канала на высоте BORE, верх рукоятки на GRIP_Z.

const BORE := GunModels.BORE
const GRIP_Z := 0.03
const ATT_SCALE := 0.95
## Расстояние от глаза до прицела в положении прицеливания (м)
const EYE := {"rds": 0.25, "holo": 0.27, "x3": 0.13, "x6": 0.12, "x10": 0.12, "thermal": 0.13}
const FLAT := "res://assets/guns/flat/%s.glb"

## Точки в координатах исходной модели (до масштаба): grip — передний верх пистолетной рукоятки (z, y),
## hand — низ цевья под левую руку, rail — место крепления прицела, irons — высота линии механического прицела.
const SPECS := {
	"ar": {"file": "res://assets/guns/m4/m4.glb", "tex": "res://assets/guns/m4/m4", "scale": 1.0,
		"bore": 0.024, "muzzle_z": -0.535, "grip": Vector2(0.045, -0.06), "hand": Vector2(-0.2, -0.012),
		"rail": Vector2(0.035, 0.05), "irons": 0.077, "side": Vector3(0.024, 0.022, -0.21), "stock_z": 0.3,
		"barrel_r": 0.009, "std_muzzle": "", "hip": Vector3(0.1, -0.125, -0.33), "ads_z": -0.15,
		"parts": {"Magazine": "mag", "Charging_Handle": "bolt", "Sight": "irons", "Sight_2": "irons", "Switch1": "irons", "Switch2": "irons"}},
	"akm": {"file": "res://assets/guns/akm/akm.glb", "tex": "res://assets/guns/akm/akm", "scale": 0.92,
		"bore": 0.0, "muzzle_z": -0.482, "grip": Vector2(0.185, -0.05), "hand": Vector2(-0.14, -0.028),
		"rail": Vector2(0.08, 0.048), "irons": 0.062, "side": Vector3(0.024, 0.0, -0.15), "stock_z": 0.46,
		"barrel_r": 0.009, "std_muzzle": "", "hip": Vector3(0.1, -0.125, -0.33), "ads_z": -0.15,
		"mag_box": [-0.08, 0.083, -0.045]},
	"smg": {"flat": "SMG_Full_West", "scale": 1.14, "grip_off": Vector2(0.028, -0.018), "barrel_r": 0.007,
		"hip": Vector3(0.095, -0.12, -0.3), "ads_z": -0.13},
	"lmg": {"flat": "Rifle_Battle_West", "scale": 1.18, "grip_off": Vector2(0.03, -0.02), "barrel_r": 0.009,
		"hip": Vector3(0.105, -0.13, -0.34), "ads_z": -0.16, "bipod": true, "long_barrel": 0.12},
	"dmr": {"flat": "Sniper_Material_West", "scale": 1.0, "grip_off": Vector2(0.03, -0.02), "barrel_r": 0.009,
		"hip": Vector3(0.1, -0.125, -0.34), "ads_z": -0.16},
	"sg": {"flat": "Shotgun_Pump_East", "scale": 1.1, "grip_off": Vector2(0.03, -0.022), "barrel_r": 0.011,
		"bore": 0.03, "hip": Vector3(0.1, -0.125, -0.32), "ads_z": -0.15, "irons": 0.074},
}

const OPTIC_MODELS := {"rds": "RedDot_West", "holo": "Holographic_West", "x3": "Magnified_West",
	"x6": "Scope_East", "x10": "Scope_West", "thermal": "Magnified_East"}

## Категории материалов стилизованных моделей по имени исходного материала.
const CAT_BY_NAME := {
	"Black": "poly", "Black_Lighter": "poly", "Grey_Darker": "poly2", "Grey_Dark": "metal", "Grey_Light": "metal2",
	"White": "bright", "Glass": "glass",
}

static var _cache := {}
static var _att_cache := {}
static var _mat_cache := {}


static func has(id: String) -> bool:
	return SPECS.has(id)


# ------------------------------------------------------------------ материалы
static func _detail(path: String) -> Texture2D:
	return load("res://assets/guns/" + path)


static func material(cat: String, camo: String) -> Material:
	var key := cat + "|" + camo
	if _mat_cache.has(key):
		return _mat_cache[key]
	var cc: Array = GunModels.CAMO.get(camo, GunModels.CAMO.black)
	var tint: Color = cc[0]
	var m := StandardMaterial3D.new()
	var col := Color(0.06, 0.06, 0.065)
	var rough := 0.62
	var metal := 0.0
	var tile := 6.0
	var nscale := 0.45
	match cat:
		"poly":
			# матовый полимер; окраска ложится на фурнитуру
			col = Color(0.045, 0.045, 0.048) if camo == "black" else tint.darkened(0.15)
			rough = 0.82
			tile = 8.0
			nscale = 0.7
		"poly2":
			col = Color(0.08, 0.08, 0.085) if camo == "black" else tint.darkened(0.3)
			rough = 0.75
			tile = 8.0
		"metal":
			# воронёная/фосфатированная сталь
			col = Color(0.085, 0.085, 0.088)
			rough = 0.52
			metal = 0.55
		"metal2":
			# ствольная коробка (анодированный алюминий); в окраске — цвет камуфляжа
			col = Color(0.13, 0.13, 0.14) if camo == "black" else tint.darkened(0.1)
			rough = 0.56
			metal = 0.4 if camo == "black" else 0.15
		"bright":
			col = Color(0.42, 0.42, 0.43)
			rough = 0.3
			metal = 1.0
		"brass":
			col = Color(0.62, 0.46, 0.2)
			rough = 0.35
			metal = 1.0
		"wood":
			col = Color(0.3, 0.14, 0.07)
			rough = 0.6
		"glass":
			m.albedo_color = Color(0.32, 0.55, 0.62, 0.22)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic_specular = 1.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mat_cache[key] = m
			return m
	m.albedo_color = col
	m.albedo_texture = _detail("detail_alb.png")
	m.roughness = rough
	m.roughness_texture = _detail("detail_rough.png")
	m.metallic = metal
	m.normal_enabled = true
	m.normal_texture = _detail("detail_nor.png")
	m.normal_scale = nscale
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = false
	_mat_cache[key] = m
	return m


static func pbr_material(tex: String, camo: String) -> Material:
	var key := tex + "|" + camo
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(tex + "_alb.jpg")
	var cc: Array = GunModels.CAMO.get(camo, GunModels.CAMO.black)
	# у АКМ своё дерево — окраски «чёрный» и «дерево» оставляют его как есть
	var plain := camo == "black" or (camo == "wood" and tex.ends_with("akm"))
	m.albedo_color = Color.WHITE if plain else Color.WHITE.lerp((cc[0] as Color).lightened(0.35), 0.45)
	var orm: Texture2D = load(tex + "_orm.png")
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	# меньше зеркального отражения неба (на солнце металл синел)
	m.metallic = 0.7
	m.metallic_texture = orm
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.normal_enabled = true
	m.normal_texture = load(tex + "_nor.png")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m


static func _cat_of(mat: Material) -> String:
	var n := mat.resource_name if mat else ""
	n = n.replace("M_PCL_Flat_", "")
	if CAT_BY_NAME.has(n):
		return CAT_BY_NAME[n]
	if n.begins_with("Brown"):
		return "wood"
	if n.begins_with("Yellow"):
		return "brass"
	# цветные полоски (синие/красные/оранжевые) на настоящем оружии не встречаются — тёмный полимер
	return "poly2"


# ------------------------------------------------------------------ разбор моделей
## Собирает геометрию модели в части {имя: {категория: SurfaceTool}} с заданным преобразованием.
static func _collect(scene_root: Node, xf: Transform3D, part_of: Callable, pbr: bool) -> Dictionary:
	var parts := {}
	for n in scene_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var gxf := xf * _local_xf(mi, scene_root)
		var nb := gxf.basis.inverse().transposed()
		var skel: Skeleton3D = null
		if mi.skin != null:
			skel = mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			var cat := "pbr" if pbr else _cat_of(mi.mesh.surface_get_material(si))
			var tri_count: int = ((idx as PackedInt32Array).size() if idx != null else verts.size()) / 3
			var bpv := 4
			if bones != null and verts.size() > 0:
				bpv = (bones as PackedInt32Array).size() / verts.size()
			for t in tri_count:
				var vi := [0, 0, 0]
				for k in 3:
					vi[k] = (idx as PackedInt32Array)[t * 3 + k] if idx != null else t * 3 + k
				var bone_name := ""
				if skel and bones != null:
					var v0: int = vi[0]
					var best := 0
					var bw := -1.0
					for k in bpv:
						var w: float = (weights as PackedFloat32Array)[v0 * bpv + k]
						if w > bw:
							bw = w
							best = (bones as PackedInt32Array)[v0 * bpv + k]
					var bi := mi.skin.get_bind_bone(best)
					bone_name = skel.get_bone_name(bi) if bi >= 0 else String(mi.skin.get_bind_name(best))
				var c := (gxf * verts[vi[0]] + gxf * verts[vi[1]] + gxf * verts[vi[2]]) / 3.0
				var part: String = part_of.call(String(mi.name), bone_name, c)
				if part == "":
					continue
				if not parts.has(part):
					parts[part] = {}
				var cats: Dictionary = parts[part]
				if not cats.has(cat):
					var st0 := SurfaceTool.new()
					st0.begin(Mesh.PRIMITIVE_TRIANGLES)
					cats[cat] = st0
				var st: SurfaceTool = cats[cat]
				for k in 3:
					var v: int = vi[k]
					st.set_normal((nb * norms[v]).normalized())
					if pbr and uvs != null:
						st.set_uv((uvs as PackedVector2Array)[v])
					st.add_vertex(gxf * verts[v])
	return parts


static func _local_xf(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Части -> {имя: [ArrayMesh, [категории по поверхностям]]}
static func _commit(parts: Dictionary, pbr: bool) -> Dictionary:
	var out := {}
	for pn in parts:
		var mesh := ArrayMesh.new()
		var cats: Array = []
		for cat in parts[pn]:
			var st: SurfaceTool = parts[pn][cat]
			st.index()
			if pbr:
				st.generate_tangents()
			st.commit(mesh)
			cats.append(cat)
		out[pn] = [mesh, cats]
	return out


static func _bones(scene_root: Node) -> Dictionary:
	var out := {}
	for n in scene_root.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		for b in sk.get_bone_count():
			out[sk.get_bone_name(b)] = sk.get_bone_global_rest(b).origin
	return out


## Разбор модели оружия (кэшируется): части, точки крепления в координатах оружия.
static func _prepare(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var sp: Dictionary = SPECS[id]
	var flat := sp.has("flat")
	var path: String = FLAT % sp.flat if flat else sp.file
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	var s: float = sp.scale
	var bones := _bones(scene)
	var bore: float
	var muzzle_z: float
	var grip: Vector2
	var hand: Vector2
	var rail: Vector2
	var irons: float
	var side: Vector3
	if flat:
		var trig: Vector3 = bones.get("Trigger", Vector3(0, -0.03, 0.05))
		var mz: Vector3 = bones.get("Attach_Muzzle", Vector3.ZERO)
		var aabb := AABB()
		var first := true
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var bb := (n as MeshInstance3D).get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		bore = float(sp.get("bore", mz.y))
		muzzle_z = mz.z if bones.has("Attach_Muzzle") else aabb.position.z
		var go: Vector2 = sp.grip_off
		grip = Vector2(trig.z + go.x, trig.y + go.y)
		var rb: Vector3 = bones.get("Attach_Rail.Bottom", Vector3(0, bore - 0.03, muzzle_z * 0.45))
		if id == "sg":
			var pump: Vector3 = bones.get("Pump", rb)
			rb = Vector3(0, pump.y - 0.03, pump.z)
		hand = Vector2(rb.z, rb.y)
		var sc: Vector3 = bones.get("Attach_Scope", Vector3(0, bore + 0.03, 0.0))
		rail = Vector2(sc.z, sc.y)
		irons = float(sp.get("irons", float((bones.get("Rear Sights", sc) as Vector3).y) + 0.012))
		var sl: Vector3 = bones.get("Attach_Rail.SideRight", bones.get("Attach_Rail.SideLeft", Vector3(-0.02, bore, rb.z)))
		side = Vector3(absf(sl.x), sl.y, sl.z)
	else:
		bore = sp.bore
		muzzle_z = sp.muzzle_z
		grip = sp.grip
		hand = sp.hand
		rail = sp.rail
		irons = sp.irons
		side = sp.side
	# масштаб и сдвиг: ось канала -> BORE, верх рукоятки -> GRIP_Z
	var off := Vector3(0, BORE - bore * s, GRIP_Z - grip.x * s)
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), off)
	var tp := func(v: Vector3) -> Vector3: return xf * v
	var part_of: Callable
	if flat:
		part_of = func(_node: String, bone: String, _c: Vector3) -> String:
			match bone:
				"Magazine":
					return "mag"
				"Bolt", "Charging Handle":
					return "bolt"
				"Pump":
					return "pump"
				"Rear Sights", "Front Sights":
					return "irons"
			return "body"
	elif sp.has("mag_box"):
		var mb: Array = sp.mag_box
		part_of = func(_node: String, _bone: String, c: Vector3) -> String:
			var mz0: float = float(mb[0]) * s + off.z
			var mz1: float = float(mb[1]) * s + off.z
			var my: float = float(mb[2]) * s + off.y
			return "mag" if (c.z > mz0 and c.z < mz1 and c.y < my) else "body"
	else:
		var pm: Dictionary = sp.get("parts", {})
		part_of = func(node: String, _bone: String, _c: Vector3) -> String:
			return String(pm.get(node, "body"))
	var parts := _collect(scene, xf, part_of, not flat)
	scene.free()
	var d := {
		"parts": _commit(parts, not flat),
		"bore": BORE,
		"muzzle": tp.call(Vector3(0, bore, muzzle_z)),
		"grip": tp.call(Vector3(0, grip.y, grip.x)),
		"hand": tp.call(Vector3(0, hand.y, hand.x)),
		"rail": tp.call(Vector3(0, rail.y, rail.x)),
		"irons": irons * s + off.y,
		"side": tp.call(side),
		"stock_z": float(sp.get("stock_z", 0.35)) * s + off.z,
		"pump_rest": tp.call(bones.get("Pump", Vector3.ZERO)),
	}
	_cache[id] = d
	return d


## Обвес из Flat Attachments: [ArrayMesh, категории, центр стекла (или null)] в собственных координатах.
static func _attachment(name: String) -> Array:
	if _att_cache.has(name):
		return _att_cache[name]
	var scene: Node3D = (load(FLAT % name) as PackedScene).instantiate()
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * ATT_SCALE), Vector3.ZERO)
	var glass_sum := Vector3.ZERO
	var glass_n := 0
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			if _cat_of(mi.mesh.surface_get_material(si)) == "glass":
				var gv: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				for v in gv:
					glass_sum += xf * v
					glass_n += 1
	var parts := _collect(scene, xf, func(_a, _b, _c): return "a", false)
	scene.free()
	var c := _commit(parts, false)
	var res := [c.a[0], c.a[1], glass_sum / glass_n if glass_n > 0 else null]
	_att_cache[name] = res
	return res


static func _add_mesh(parent: Node3D, mesh_cats: Array, camo: String, tex: String, xf := Transform3D()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_cats[0]
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cats: Array = mesh_cats[1]
	for i in cats.size():
		var m: Material = pbr_material(tex, camo) if cats[i] == "pbr" else material(cats[i], camo)
		mi.set_surface_override_material(i, Mats.viewmodel(m))
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ сборка
## Тот же словарь, что GunModels.build, плюс "anchors" — точки слотов обвеса для оружейной.
static func build(id: String, att: Dictionary, arms := true) -> Dictionary:
	var sp: Dictionary = SPECS[id]
	var d := _prepare(id)
	var camo: String = att.get("camo", "black")
	var tex: String = sp.get("tex", "")
	var root := Node3D.new()
	var parts: Dictionary = d.parts
	var optic: String = att.get("optic", "iron")
	_add_mesh(root, parts.body, camo, tex)
	if parts.has("bolt"):
		_add_mesh(root, parts.bolt, camo, tex)
	if parts.has("irons") and optic == "iron":
		_add_mesh(root, parts.irons, camo, tex)
	var mag: Node3D = null
	if parts.has("mag"):
		mag = Node3D.new()
		root.add_child(mag)
		var mmi := _add_mesh(mag, parts.mag, camo, tex)
		if att.get("mag", "std") == "ext":
			# увеличенный магазин: длиннее вниз от горловины
			var top: float = (d.grip as Vector3).y + 0.02
			mmi.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.3, 1.08)), Vector3(0, top - top * 1.3, 0))
	var pump: Node3D = null
	if parts.has("pump"):
		pump = Node3D.new()
		root.add_child(pump)
		_add_mesh(pump, parts.pump, camo, tex)

	var b := GunModels.B.new()
	var mats := GunModels._mats(camo)
	var muzzle: Vector3 = d.muzzle
	var r: float = sp.barrel_r
	# удлинённый ствол: дополнительный участок трубы перед штатным дульным
	var ext := float(sp.get("long_barrel", 0.0)) + (0.07 if att.get("barrel", "std") == "long" else 0.0)
	if ext > 0.0:
		b.cz("metal", muzzle.z, muzzle.z - ext, muzzle.y, r, r, 10)
		muzzle.z -= ext
	var mk: String = att.get("muzzle", "none")
	if mk == "supp":
		var sup := _attachment("Suppressor_West")
		_add_mesh(root, sup, "black", "", Transform3D(Basis(), muzzle))
		var sb: AABB = (sup[0] as ArrayMesh).get_aabb()
		muzzle.z += sb.position.z
	elif mk != "none":
		muzzle.z = GunModels._muzzle(b, mk, muzzle.z + 0.005, r, muzzle.y)
	# прицел
	var sight_y: float = d.irons
	var glass_pos = null
	var rail: Vector3 = d.rail
	if optic != "iron" and OPTIC_MODELS.has(optic):
		var om := _attachment(OPTIC_MODELS[optic])
		_add_mesh(root, om, "black", "", Transform3D(Basis(), rail))
		if om[2] != null:
			glass_pos = (om[2] as Vector3) + rail
			sight_y = (glass_pos as Vector3).y
		if optic in ["rds", "holo"] and glass_pos != null:
			# светящаяся марка на стекле коллиматора/голографа
			var dot := QuadMesh.new()
			dot.size = Vector2(0.0035, 0.0035) if optic == "rds" else Vector2(0.006, 0.006)
			GunModels._add(root, dot, mats.red, Transform3D(Basis(), (glass_pos as Vector3) + Vector3(0, 0, 0.001)))
	# цевьё / рукоятка
	var hand: Vector3 = d.hand
	var fg: String = att.get("grip", "none")
	if fg == "vert" or fg == "angled":
		_add_mesh(root, _attachment("Foregrip_West" if fg == "vert" else "Foregrip_East"), "black", "", Transform3D(Basis(), hand))
	if att.get("laser", "none") == "laser":
		var sd: Vector3 = d.side
		_add_mesh(root, _attachment("Laser_West"), "black", "", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), sd))
	if sp.get("bipod", false):
		# сошки, сложенные вдоль ствола
		var bz := muzzle.z + 0.16
		for sx in [-1.0, 1.0]:
			b.box("metal", Vector3(0.011 * sx, hand.y - 0.012, bz + 0.1), Vector3(0.007, 0.007, 0.2))
			b.box("poly", Vector3(0.011 * sx, hand.y - 0.012, bz), Vector3(0.012, 0.012, 0.018))
		b.box("metal", Vector3(0, hand.y - 0.004, bz + 0.2), Vector3(0.03, 0.014, 0.03))
	if not b.st.is_empty():
		b.commit(root, mats)

	var grip: Vector3 = d.grip
	# глаз за прицелом на своём расстоянии; с механикой — у приклада, как раньше
	var ads_z: float = float(sp.ads_z)
	if EYE.has(optic):
		ads_z = minf(ads_z, -float(EYE[optic]) - rail.z)
	if arms:
		var gz := grip.z
		var gy := grip.y
		_arm_r(root, gz, gy)
		var lhost: Node3D = pump if pump else root
		var hz := hand.z
		if pump:
			hz = (d.pump_rest as Vector3).z
		if fg == "vert":
			GunModels._arm(lhost, Vector3(-0.2, hand.y - 0.28, hz + 0.26), Vector3(-0.03, hand.y - 0.09, hz + 0.05), Vector3(0.0, hand.y - 0.05, hz + 0.004), 2, true)
		else:
			GunModels._arm(lhost, Vector3(-0.2, hand.y - 0.26, hz + 0.27), Vector3(-0.034, hand.y - 0.05, hz + 0.055), Vector3(-0.004, hand.y - 0.03, hz), 1, true)
	var anchors := {
		"muzzle": Vector3(0, muzzle.y, muzzle.z + 0.02),
		"barrel": Vector3(0, muzzle.y + r, lerpf(muzzle.z, hand.z, 0.35)),
		"optic": rail + Vector3(0, 0.03 if optic != "iron" else 0.0, 0),
		"grip": Vector3(0, hand.y - (0.03 if fg != "none" else 0.0), hand.z),
		"mag": Vector3(0, grip.y - 0.08, lerpf(grip.z, hand.z, 0.3)),
		"stock": Vector3(0, grip.y + 0.01, d.stock_z if not sp.has("flat") else grip.z + 0.2),
		"laser": d.side,
		"camo": Vector3(0, BORE + 0.01, grip.z - 0.08),
	}
	return {"root": root, "mag": mag, "pump": pump, "muzzle": muzzle, "hip": sp.hip,
		"ads": Vector3(0.0, -sight_y, ads_z), "parts": [], "length": absf(muzzle.z) + 0.3,
		"anchors": anchors, "scope_glass": glass_pos}


## Правая рука на пистолетной рукоятке (из GunModels, координаты от верха рукоятки).
static func _arm_r(root: Node3D, gz: float, gy: float) -> void:
	GunModels._arm(root, Vector3(0.17, gy - 0.22, gz + 0.27), Vector3(0.016, gy - 0.1, gz + 0.045),
		Vector3(0.003, gy - 0.07, gz + 0.012), 0)
