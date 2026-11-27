class_name FarCrowd
extends Node3D
## Дальние солдаты одним вызовом отрисовки на вид солдата.
##
## Каждый скиннутый солдат — отдельный вызов отрисовки, а с вида на базу их в кадре 25–40 (на Mali упор
## именно в вызовы). Живой противник дальше DIST метров (с поправкой на зум прицела — в оптике дальность
## растёт, чтобы «статуи» не были видны) прячет свой скелетный меш и рисуется экземпляром MultiMesh:
## упрощённый меш (LOD 1), один раз «запечённый» в позе стоящего солдата этого вида. Приседание — сжатие по
## высоте. На ~15 px высоты потеря анимации ходьбы не заметна, а красная метка HUD и попадания не зависят
## от отрисовки (капсула и позиция противника те же). Убитые остаются скиннутыми (поза падения).

const DIST := 60.0          # м при обычном FOV (75°)
const HYST := 4.0           # м — чтобы солдат на границе не мигал между режимами
const MAX_D := 320.0
const SHADOW_D := 20.0       # м — дальше солдат тень не отбрасывает        # дальше солдат не рисуется вовсе (как visibility_range_end у LOD 1)
const ATLAS := ["soldier_a", "soldier_b", "soldier_c"]

var _mm: Array[MultiMeshInstance3D] = []
var _baked: Array[bool] = [false, false, false]
var enabled := not ("--nocrowd" in OS.get_cmdline_user_args())


func _ready() -> void:
	# после всех противников: их позы и положения в этом кадре уже обновлены
	process_priority = 100
	for k in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mats.soldier(ATLAS[k])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# преобразования ставятся в _process каждый кадр — интерполяция физики не нужна
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# экземпляры по всей карте — отсечение по общей коробке (вызов будет, только если есть кто-то в кадре)
		mmi.custom_aabb = AABB(Vector3(-3000, -500, -3000), Vector3(6000, 1500, 6000))
		add_child(mmi)
		_mm.append(mmi)


## Запечь позу скелета в статичный меш (жёсткая привязка: одна кость на вершину).
static func bake(src: ArrayMesh, sk: Skeleton3D, skin: Skin) -> ArrayMesh:
	var arr := src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var xf: Array[Transform3D] = []
	for i in skin.get_bind_count():
		xf.append(sk.get_bone_global_pose(skin.get_bind_bone(i)) * skin.get_bind_pose(i))
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	ov.resize(v.size())
	on.resize(v.size())
	for i in v.size():
		var t: Transform3D = xf[bones[i * 4]]
		ov[i] = t * v[i]
		on[i] = (t.basis * n[i]).normalized()
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	out[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
	out[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var lists: Array = [[], [], []]
	var thr := 1.0e9
	if cam and enabled:
		# в прицеле (узкий FOV) порог растёт пропорционально увеличению
		thr = DIST * tan(deg_to_rad(37.5)) / tan(deg_to_rad(clampf(cam.fov, 5.0, 120.0) * 0.5))
	var cp: Vector3 = cam.global_position if cam else Vector3.ZERO
	var planes: Array[Plane] = cam.get_frustum() if cam else []
	for e in Game.enemies:
		if not is_instance_valid(e) or e.skel == null:
			continue
		# тень солдата (вызов в каждом слое теней) — только вблизи
		var sh := e.global_position.distance_squared_to(cp) < SHADOW_D * SHADOW_D
		if sh != e.shadow_on and not e._lod_mis.is_empty():
			e.shadow_on = sh
			e._lod_mis[0].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var far := false
		if e.state != Enemy.St.DEAD and thr < MAX_D:
			var d := e.global_position.distance_to(cp)
			far = d > (thr - HYST if e.crowd else thr + HYST) and d < MAX_D
			if far and not _baked[e.kind]:
				# поза берётся у первого стоящего спокойного солдата этого вида (пост, ожидание; не целящегося и не в тревоге)
				if (e.state == Enemy.St.IDLE or e.state == Enemy.St.PATROL) and not e.sees and absf(e.aim_pitch) < 0.05 and e.crouch < 0.05 and Vector2(e.velocity.x, e.velocity.z).length() < 0.1 and e._posed:
					_mm[e.kind].multimesh.mesh = bake(SoldierRig.mesh(e.kind, 1), e.skel, SoldierRig.skin(e.skel))
					_baked[e.kind] = true
				else:
					far = false
		if far != e.crowd:
			e.set_crowd(far)
		if far and _in_view(planes, e.global_position + Vector3(0, 0.9, 0)):
			# вне кадра не рисуем (экземпляры MultiMesh по отдельности не отсекаются)
			var t: Transform3D = e.skel.global_transform
			if e.crouch > 0.01:
				t = t * Transform3D(Basis.from_scale(Vector3(1.0, 1.0 - 0.3 * e.crouch, 1.0)), Vector3.ZERO)
			(lists[e.kind] as Array).append(t)
	for k in 3:
		var mm := _mm[k].multimesh
		var l: Array = lists[k]
		if mm.instance_count < l.size():
			mm.instance_count = l.size() + 8
		mm.visible_instance_count = l.size()
		for i in l.size():
			mm.set_instance_transform(i, l[i])
		_mm[k].visible = l.size() > 0


static func _in_view(planes: Array[Plane], p: Vector3) -> bool:
	for pl in planes:
		if pl.distance_to(p) > 1.2:
			return false
	return true
