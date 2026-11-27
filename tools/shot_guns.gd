extends SceneTree
## Снимки моделей сбоку (ортографически) для проверки ориентации и вида.
## godot --path . --resolution 900x500 --script res://tools/shot_guns.gd -- <res-путь> <имя> [вид: x|z|y]
## Вид x: камера на +X смотрит в -X (справа на экране = -Z). Вид z: камера на +Z (справа = +X). Вид y: сверху.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new()
	get_root().add_child(root)
	var inst: Node3D = (load(a[0]) as PackedScene).instantiate() if a[0].ends_with(".glb") or a[0].ends_with(".gltf") else null
	root.add_child(inst)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.33)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(Vector3(1, 2, 1.5), Vector3.ZERO, Vector3.UP)
	await process_frame
	var bb := AABB()
	var first := true
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	print("AABB ", bb)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) * 1.15
	root.add_child(cam)
	var c := bb.get_center()
	var view := a[2] if a.size() > 2 else "x"
	if view == "x":
		cam.look_at_from_position(c + Vector3(5, 0, 0), c, Vector3.UP)
	elif view == "z":
		cam.look_at_from_position(c + Vector3(0, 0, 5), c, Vector3.UP)
	else:
		cam.look_at_from_position(c + Vector3(0, 5, 0), c, Vector3.FORWARD)
	cam.current = true
	if view == "x" and a.size() > 3:
		# сетка каждые 5 см с подписями (z по горизонтали, y по вертикали) для снятия координат
		var cl := CanvasLayer.new()
		root.add_child(cl)
		var ctl := Grid.new()
		ctl.c = c
		ctl.ppm = get_root().get_visible_rect().size.y / cam.size
		ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
		cl.add_child(ctl)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("user://shot_%s_%s.png" % [a[1], view])
	quit()


class Grid extends Control:
	var c: Vector3
	var ppm := 1.0
	func _draw() -> void:
		var sz := get_viewport_rect().size
		var f := ThemeDB.fallback_font
		for i in range(-40, 41):
			var z := snappedf(c.z, 0.05) + i * 0.05
			var x := sz.x * 0.5 - (z - c.z) * ppm
			if x < 0 or x > sz.x:
				continue
			draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(1, 1, 0, 0.35 if i % 2 == 0 else 0.15), 1.0)
			if i % 2 == 0:
				draw_string(f, Vector2(x + 2, 12), "%.2f" % z, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 0.3))
		for i in range(-20, 21):
			var y := snappedf(c.y, 0.05) + i * 0.05
			var py := sz.y * 0.5 - (y - c.y) * ppm
			if py < 0 or py > sz.y:
				continue
			draw_line(Vector2(0, py), Vector2(sz.x, py), Color(0, 1, 1, 0.35 if i % 2 == 0 else 0.15), 1.0)
			draw_string(f, Vector2(2, py - 2), "%.2f" % y, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 1, 1))
