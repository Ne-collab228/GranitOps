extends SceneTree
# Находит направление на солнце в HDRI (самый яркий пиксель панорамы).
func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sky/sky_2k.hdr"))
	img.convert(Image.FORMAT_RGBF)
	var w := img.get_width()
	var h := img.get_height()
	var best := 0.0
	var bx := 0
	var by := 0
	var sum := Vector3.ZERO
	var horizon := Vector3.ZERO
	var hn := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var c := img.get_pixel(x, y)
			var l := c.r + c.g + c.b
			if l > best:
				best = l
				bx = x
				by = y
			if y > h * 0.44 and y < h * 0.49:
				horizon += Vector3(minf(c.r, 4.0), minf(c.g, 4.0), minf(c.b, 4.0))
				hn += 1
	var u := float(bx) / w
	var v := float(by) / h
	var th := u * TAU
	var ph := v * PI
	var dir := Vector3(sin(th) * sin(ph), cos(ph), -cos(th) * sin(ph))
	print("size ", w, "x", h, " brightest ", best, " at uv ", u, ",", v)
	print("SUN_DIR = Vector3(%.3f, %.3f, %.3f)" % [dir.x, dir.y, dir.z])
	print("elevation deg ", rad_to_deg(asin(dir.y)))
	print("horizon color ", horizon / hn)
	quit()
