class_name Grenade
extends RigidBody3D
## Осколочная граната с запалом.

var fuse := 3.2


func _ready() -> void:
	collision_layer = Game.L_DYN
	collision_mask = Game.L_WORLD
	mass = 0.4
	continuous_cd = true
	angular_damp = 2.0
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.9
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.07
	cs.shape = s
	add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.12
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = Mats.flat(Color(0.16, 0.2, 0.12), 0.7, 0.3)
	add_child(mi)
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_bounce)


func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		Game.fx.explosion(global_position, 10.0, 180.0)
		queue_free()


func _bounce(_body: Node) -> void:
	if linear_velocity.length() > 1.5:
		Sfx.play_at("bounce", global_position, -6.0, randf_range(0.9, 1.1), 4.0, 40.0)
