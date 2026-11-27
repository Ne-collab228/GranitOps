extends SceneTree
## Проверка навигации: рёбра по всем кускам карты (какие делят одно место более 2 раз).
## Запуск: godot --headless --path . --script res://tools/nav_check.gd -- valley 16


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var key: String = a[0]
	var n := int(a[1])
	var q := 0.25 * 0.01
	var edges := {}
	for i in n:
		var nm: NavigationMesh = load("res://assets/nav/%s/%d.res" % [key, i])
		var v := nm.vertices
		for p in nm.get_polygon_count():
			var poly := nm.get_polygon(p)
			for k in poly.size():
				var pa: Vector3 = v[poly[k]]
				var pb: Vector3 = v[poly[(k + 1) % poly.size()]]
				var ka := Vector3i((pa / q).round())
				var kb := Vector3i((pb / q).round())
				var lo := ka
				var hi := kb
				if ka.x > kb.x or (ka.x == kb.x and (ka.y > kb.y or (ka.y == kb.y and ka.z > kb.z))):
					lo = kb
					hi = ka
				var k2 := "%s|%s" % [lo, hi]
				if not edges.has(k2):
					edges[k2] = []
				edges[k2].append([i, p, pa, pb])
	var bad := 0
	for k in edges:
		var l: Array = edges[k]
		if l.size() > 2:
			bad += 1
			if bad < 12:
				print(l.size(), " ", l.map(func(e): return "t%d p%d" % [e[0], e[1]]), " ", l[0][2], l[0][3])
	print("рёбер >2 использований: ", bad)
	quit()
