class_name Mats
extends RefCounted
## Библиотека материалов (PBR-текстуры Poly Haven, CC0).

# ключ -> [текстура, размер тайла в метрах, тип поверхности, оттенок]
const DEFS := {
	"concrete": ["concrete_wall_003", 3.0, "concrete", Color(0.74, 0.73, 0.7)],
	"floor": ["concrete_floor_worn_001", 3.0, "concrete"],
	"plaster": ["worn_cracked_plaster", 3.0, "concrete"],
	"plaster_tan": ["worn_cracked_plaster", 3.0, "concrete", Color(0.93, 0.84, 0.68)],
	"iron": ["corrugated_iron_02", 2.0, "sheet"],
	"rust": ["rusty_metal_02", 2.0, "metal"],
	"container": ["container_side", 2.6, "metal"],
	"container_blue": ["container_side", 2.6, "metal", Color(0.42, 0.6, 0.85)],
	"container_green": ["container_side", 2.6, "metal", Color(0.5, 0.72, 0.45)],
	"container_grey": ["container_side", 2.6, "metal", Color(0.72, 0.72, 0.7)],
	"plate": ["metal_plate", 2.0, "metal"],
	"plate_dark": ["metal_plate", 1.0, "metal", Color(0.32, 0.33, 0.34)],
	"wood": ["wood_planks_grey", 2.0, "wood"],
	"wood_dark": ["wood_planks_grey", 2.0, "wood", Color(0.62, 0.5, 0.4)],
	"asphalt": ["asphalt_02", 4.0, "concrete"],
	"sandbag": ["hessian_230", 0.7, "dirt", Color(0.86, 0.78, 0.62)],
	"canvas": ["hessian_230", 0.5, "dirt", Color(0.36, 0.4, 0.28)],
	"green": ["green_metal_rust", 2.0, "metal"],
	"rock": ["rock_boulder_dry", 3.0, "concrete", Color(0.66, 0.63, 0.58)],
	"bark": ["bark_brown_02", 1.2, "wood"],
	# --- здания (scripts/bld.gd)
	"stucco_blue": ["concrete_wall_003", 3.0, "concrete", Color(0.68, 0.78, 0.84)],
	"stucco_yellow": ["concrete_wall_003", 3.0, "concrete", Color(0.96, 0.83, 0.6)],
	"slate": ["corrugated_iron_02", 1.0, "sheet", Color(0.95, 0.94, 0.9)],
	"roof_red": ["corrugated_iron_02", 1.5, "sheet", Color(0.8, 0.42, 0.33)],
}

static var _cache := {}
static var _normal_mats: Array = []
static var normals_on := true


static func surf(key: String) -> String:
	if DEFS.has(key):
		return DEFS[key][2]
	return "concrete"


static func mesh_instances(root: Node) -> Array:
	var out: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		out.append(root)
	return out


static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	if key.begins_with("#"):
		return flat(Color(key), 0.9)
	if key.begins_with("!"):
		return emissive(Color("#" + key.substr(1)), 2.5)
	if key == "fence":
		var f := StandardMaterial3D.new()
		f.albedo_texture = load("res://assets/gen/fence.png")
		f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		f.alpha_scissor_threshold = 0.35
		f.cull_mode = BaseMaterial3D.CULL_DISABLED
		f.uv1_scale = Vector3(1.6, 1.6, 1.6)
		f.roughness = 0.6
		f.metallic = 0.5
		f.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cache[key] = f
		return f
	if key == "glass":
		# стекло окон: тёмное, гладкое, отражает небо (непрозрачное — дешевле)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.06, 0.075, 0.08)
		gm.metallic = 0.15
		gm.metallic_specular = 0.9
		gm.roughness = 0.12
		gm.vertex_color_use_as_albedo = true
		_cache[key] = gm
		return gm
	if key == "grime":
		# подтёки и пятна на фасадах (наклейки с альфой, тени не отбрасывают)
		var gr := StandardMaterial3D.new()
		gr.albedo_texture = load("res://assets/gen/grime.png")
		gr.albedo_color = Color(0.2, 0.18, 0.15, 0.55)
		gr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gr.roughness = 1.0
		gr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_cache[key] = gr
		return gr
	if key == "pine":
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = load("res://assets/gen/pine.png")
		pm.uv1_scale = Vector3(0.6, 0.6, 0.6)
		pm.roughness = 1.0
		pm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = pm
		return pm
	var d: Array = DEFS[key]
	var m := ORMMaterial3D.new()
	var base: String = "res://assets/tex/%s" % d[0]
	m.albedo_texture = load(base + "_diff.jpg")
	m.orm_texture = load(base + "_arm.jpg")
	m.normal_texture = load(base + "_nor.jpg")
	m.normal_enabled = normals_on
	m.ao_enabled = true
	var s := 1.0 / float(d[1])
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if d.size() > 3:
		m.albedo_color = d[3]
	# цвет вершин несёт затенение у земли (Geo.finish); у мешей без цвета он белый
	m.vertex_color_use_as_albedo = true
	_normal_mats.append(m)
	_cache[key] = m
	return m


static func flat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%.2f" % [color.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	_cache[key] = m
	return m


static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "emi_%s_%.1f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


## Текстурный материал без освещения (частицы, вспышки, декали).
static func sprite(tex_name: String, additive := false, billboard := false, particles := false) -> StandardMaterial3D:
	var key := "spr_%s_%s_%s_%s" % [tex_name, additive, billboard, particles]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/gen/%s.png" % tex_name)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if particles:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	elif billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	_cache[key] = m
	return m


## Растительность: альфа-тест, двусторонняя.
static func foliage(tex_name: String) -> StandardMaterial3D:
	var key := "fol_" + tex_name
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/gen/%s.png" % tex_name)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.26, 0.12)
	_cache[key] = m
	return m


static func soldier(atlas: String) -> StandardMaterial3D:
	var key := "sol_" + atlas
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/gen/%s.png" % atlas)
	m.roughness = 0.88
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# излучение включено всегда (чёрное), чтобы тепловизор менял лишь цвет без перекомпиляции шейдера
	m.emission_enabled = true
	m.emission = Color.BLACK
	m.emission_energy_multiplier = 0.0
	_cache[key] = m
	return m


## Остывший солдат (убит): без «тепла» в тепловизоре.
static func soldier_cold(atlas: String) -> StandardMaterial3D:
	var key := "solc_" + atlas
	if _cache.has(key):
		return _cache[key]
	var m := soldier(atlas).duplicate() as StandardMaterial3D
	_cache[key] = m
	_cold.append(m)
	# дубликат копирует текущее «горячее» излучение — сразу выставить холодное
	m.emission = Color(0.5, 0.5, 0.5) if thermal_on else Color.BLACK
	m.emission_energy_multiplier = 0.35 if thermal_on else 0.0
	return m


static var _cold: Array = []
static var thermal_on := false


## Тепловизор: живые солдаты светятся, убитые чуть тёплые.
static func set_thermal(on: bool) -> void:
	thermal_on = on
	for k in _cache:
		if String(k).begins_with("sol_"):
			var m := _cache[k] as StandardMaterial3D
			m.emission = Color(1, 0.97, 0.95) if on else Color.BLACK
			m.emission_energy_multiplier = 2.6 if on else 0.0
	for m in _cold:
		(m as StandardMaterial3D).emission = Color(0.5, 0.5, 0.5) if on else Color.BLACK
		(m as StandardMaterial3D).emission_energy_multiplier = 0.35 if on else 0.0


## Копия материала для оружия от первого лица: свой FOV и защита от «протыкания» стен.
## false — витрина оружейной: материалы без подмены FOV оружия от первого лица.
static var vm_enabled := true


static func viewmodel(src: Material) -> Material:
	if src == null or not vm_enabled:
		return src
	var key := "vm_%d" % src.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var m := src.duplicate() as BaseMaterial3D
	if m:
		m.use_fov_override = true
		m.fov_override = 52.0
		m.use_z_clip_scale = true
		m.z_clip_scale = 0.35
	_cache[key] = m
	return m


## Регистрирует материалы импортированной модели (для отключения карт нормалей на слабых GPU).
static func register_scene(root: Node) -> void:
	for mi in mesh_instances(root):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as BaseMaterial3D
			if m and not _normal_mats.has(m) and m.normal_texture != null:
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				_normal_mats.append(m)
				m.normal_enabled = normals_on


static func apply_quality() -> void:
	normals_on = bool(Settings.data.normal_maps)
	for m in _normal_mats:
		(m as BaseMaterial3D).normal_enabled = normals_on
