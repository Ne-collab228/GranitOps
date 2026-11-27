extends Node3D
## Осмотр моделей машин: печатает дерево узлов (меши, габариты, треугольники, материалы) и снимает
## ряд машин с трёх сторон в user://veh_probe_*.png. Запуск:
## G --path . --rendering-method gl_compatibility --resolution 960x540 --position 20,40 res://scenes/vehicle_probe.tscn

const FILES := ["uaz469/uaz469.fbx", "uaz452/uaz_452.fbx", "uaz452/uaz_destroyed.fbx", "rgs/Pickup.fbx", "rgs/SUV.fbx",
	"rgs/Sedan.fbx", "rgs/Hatchback.fbx", "rgs/Van.fbx", "rgs/Truck.fbx"]


func _dump(n: Node, depth: int, xf: Transform3D) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	var line := "  ".repeat(depth) + "%s (%s)" % [n.name, n.get_class()]
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		var tris := 0
		var mats := []
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat := m.surface_get_material(s)
			mats.append(mat.resource_name if mat else "-")
		var bb: AABB = t * m.get_aabb()
		line += " tris=%d aabb_pos=%s size=%s mats=%s" % [tris, bb.position, bb.size, mats]
	elif n is Node3D:
		line += " pos=%s rot=%s scale=%s" % [(n as Node3D).position, (n as Node3D).rotation_degrees, (n as Node3D).scale]
	print(line)
	for c in n.get_children():
		_dump(c, depth + 1, t)


func _total_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var bb: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = bb if acc[0] == null else (acc[0] as AABB).merge(bb)
	for c in n.get_children():
		_total_aabb(c, t, acc)


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Vector3(-0.4, 0.8, 0.5) * 10.0, Vector3.ZERO)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var x := 0.0
	for f in FILES:
		var ps: PackedScene = load("res://assets/vehicles/src/" + f)
		if ps == null:
			print("НЕТ ", f)
			continue
		var inst := ps.instantiate() as Node3D
		print("=== ", f)
		_dump(inst, 0, Transform3D())
		var acc := [null]
		_total_aabb(inst, Transform3D(), acc)
		var bb: AABB = acc[0]
		print("ИТОГО габариты: ", bb.size, " низ y=", bb.position.y, " центр=", bb.get_center())
		# нормируем к длине ~4.5 м по наибольшей горизонтальной стороне, ставим на пол
		var k := 4.5 / maxf(bb.size.x, bb.size.z)
		inst.scale *= k
		inst.position = Vector3(x, -bb.position.y * k, 0) - Vector3(bb.get_center().x * k, 0, bb.get_center().z * k)
		add_child(inst)
		var lbl := Label3D.new()
		lbl.text = f.get_file()
		lbl.position = Vector3(x, 3.5, 0)
		lbl.pixel_size = 0.01
		add_child(lbl)
		x += 7.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var n := int(x / 7.0)
	for i in n:
		var c := Vector3(i * 7.0, 1.0, 0)
		for side in [1.0, -1.0]:
			cam.look_at_from_position(c + Vector3(5.5 * side, 2.6, 6.5), c)
			for k in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://veh_probe_%d_%s.png" % [i, "a" if side > 0 else "b"])
	get_tree().quit()
