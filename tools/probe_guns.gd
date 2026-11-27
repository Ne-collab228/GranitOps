extends SceneTree
## Печатает устройство моделей оружия: узлы, AABB мешей, кости. Запуск:
## godot --headless --path . --script res://tools/probe_guns.gd -- <файлы через запятую>

func _init() -> void:
	var files: PackedStringArray = OS.get_cmdline_user_args()[0].split(",")
	for f in files:
		var ps: PackedScene = load(f)
		var root: Node = ps.instantiate()
		print("=== ", f)
		_walk(root, root, 0)
		root.free()
	quit()


func _walk(n: Node, root: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + n.name + " <" + n.get_class() + ">"
	if n is Node3D:
		var gx := _gxf(n as Node3D, root)
		line += " pos=" + str(gx.origin.snapped(Vector3.ONE * 0.001))
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		var bb := m.get_aabb()
		line += " aabb=" + str(bb.position.snapped(Vector3.ONE * 0.001)) + "+" + str(bb.size.snapped(Vector3.ONE * 0.001)) + " surf=" + str(m.get_surface_count())
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			line += " [" + (mat.resource_name if mat else "-") + (" " + str((mat as BaseMaterial3D).albedo_color) if mat is BaseMaterial3D else "") + "]"
	print(line)
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		for b in sk.get_bone_count():
			print("  ".repeat(depth + 1), "bone ", b, " ", sk.get_bone_name(b), " parent=", sk.get_bone_parent(b), " grest=", sk.get_bone_global_rest(b).origin.snapped(Vector3.ONE * 0.001))
	for c in n.get_children():
		_walk(c, root, depth + 1)


func _gxf(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
