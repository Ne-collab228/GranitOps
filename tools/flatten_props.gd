extends SceneTree
## Склеивает модели пропсов (assets/models/<m>/<m>.gltf) в один меш: по поверхности на материал,
## и генерирует LOD (склейка в игре через SurfaceTool теряла LOD импорта — треугольников становилось вдвое больше).
## Результат: assets/models_flat/<m>.res, его грузит Level._prop. Запуск после изменения моделей:
##   Godot --headless --path . -s tools/flatten_props.gd
const SKIP := ["bolt_action_rifle_7_62", "service_pistol"]

func _init() -> void:
	var dir := DirAccess.open("res://assets/models")
	for model in dir.get_directories():
		if model in SKIP:
			continue
		var path := "res://assets/models/%s/%s.gltf" % [model, model]
		if not ResourceLoader.exists(path):
			continue
		var probe: Node3D = (load(path) as PackedScene).instantiate()
		var by_mat := {}
		var order: Array = []
		var stack: Array[Node] = [probe]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			for ch in nd.get_children():
				stack.append(ch)
			if not (nd is MeshInstance3D) or (nd as MeshInstance3D).mesh == null:
				continue
			var m := nd as MeshInstance3D
			var xf := Transform3D()
			var n: Node = m
			while n != probe and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for si in m.mesh.get_surface_count():
				var mat: Material = m.get_surface_override_material(si)
				if mat == null:
					mat = m.mesh.surface_get_material(si)
				if not by_mat.has(mat):
					var st0 := SurfaceTool.new()
					st0.begin(Mesh.PRIMITIVE_TRIANGLES)
					by_mat[mat] = st0
					order.append(mat)
				(by_mat[mat] as SurfaceTool).append_from(m.mesh, si, xf)
		var im := ImporterMesh.new()
		for mat in order:
			var st: SurfaceTool = by_mat[mat]
			st.index()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, mat)
		im.generate_lods(25.0, 60.0, [])
		var mesh := im.get_mesh()
		var tris := 0
		for si in mesh.get_surface_count():
			var idx = mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
			tris += (idx as PackedInt32Array).size() / 3 if idx != null else 0
		var err := ResourceSaver.save(mesh, "res://assets/models_flat/%s.res" % model, ResourceSaver.FLAG_COMPRESS)
		print("%-28s поверхностей=%d треугольников=%d lod=%d err=%d" % [model, mesh.get_surface_count(), tris,
			im.get_surface_lod_count(0) if im.get_surface_count() > 0 else 0, err])
		probe.free()
	quit()
