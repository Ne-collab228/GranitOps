extends SceneTree
## Путь через границы кусков: godot --headless --path . --script res://tools/nav_path_test.gd -- valley 16
## Берёт центры соседних кусков по полигонам и ищет путь между ними через NavigationServer3D.


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var key: String = a[0]
	var n := int(a[1])
	var map := root.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.25)
	NavigationServer3D.map_set_cell_height(map, 0.2)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(map, 0.01)
	var centers: Array[Vector3] = []
	for i in n:
		var nm: NavigationMesh = load("res://assets/nav/%s/%d.res" % [key, i])
		var reg := NavigationRegion3D.new()
		reg.navigation_mesh = nm
		root.add_child(reg)
		var v := nm.vertices
		var c := Vector3.ZERO
		var best := 1e9
		var sum := Vector3.ZERO
		for p in nm.get_polygon_count():
			for id in nm.get_polygon(p):
				sum += v[id]
		sum /= maxf(1.0, float(nm.get_polygon_count()) * 4.0)
		for p in nm.get_polygon_count():
			var pc := Vector3.ZERO
			var poly := nm.get_polygon(p)
			for id in poly:
				pc += v[id]
			pc /= poly.size()
			if pc.distance_to(sum) < best:
				best = pc.distance_to(sum)
				c = pc
		centers.append(c)
	await physics_frame
	await physics_frame
	for _f in 5:
		await physics_frame
	NavigationServer3D.map_force_update(map)
	print("итерация карты ", NavigationServer3D.map_get_iteration_id(map), " регионов ", NavigationServer3D.map_get_regions(map).size())
	var ok := 0
	var fail := 0
	for i in n:
		for j in range(i + 1, n):
			if centers[i].distance_to(centers[j]) > 260.0:
				continue
			var path := NavigationServer3D.map_get_path(map, centers[i], centers[j], true)
			var end_ok := path.size() > 1 and path[path.size() - 1].distance_to(centers[j]) < 3.0
			if end_ok:
				ok += 1
			else:
				fail += 1
				print("нет пути ", i, " -> ", j, " ", path.size(), " ", centers[i], centers[j], " ", path[path.size()-1] if path.size() > 0 else "-")
	print("пути между соседними кусками: ок ", ok, ", нет ", fail)
	quit()
