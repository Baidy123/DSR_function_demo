extends SceneTree

const CameraScript = preload("res://scripts/systems/player_camera.gd")
var checks := 0
var failed := 0
var world: Node3D
var camera: Camera3D
var actor: TestActor

class TestActor extends CharacterBody3D:
	var height := 1.75
	func get_body_height() -> float:
		return height


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	actor = TestActor.new()
	actor.name = "Actor"
	actor.position.x = 2.0
	world.add_child(actor)
	var actor_shape := CollisionShape3D.new()
	actor_shape.shape = CapsuleShape3D.new()
	actor_shape.position.y = 0.875
	actor.add_child(actor_shape)
	camera = CameraScript.new()
	camera.name = "Camera"
	camera.player_path = ^"../Actor"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 1, 8)
	world.add_child(camera)
	camera.make_current()
	var shared := StandardMaterial3D.new()
	shared.albedo_color = Color(0.25, 0.5, 0.8, 1)
	shared.roughness = 0.4
	shared.albedo_texture = GradientTexture2D.new()
	var extra_pass := ORMMaterial3D.new()
	extra_pass.albedo_color.a = 0.6
	extra_pass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shared.next_pass = extra_pass
	var first := _box(Vector3(2, 1, 4), Vector3(0.8, 2, 0.4), shared)
	var second := _box(Vector3(2, 1, 2), Vector3(0.8, 2, 0.4), shared)
	var unrelated := _box(Vector3(-3, 1, 4), Vector3(1, 2, 0.4), shared)
	var behind := _box(Vector3(2, 1, -2), Vector3(1, 2, 0.4), shared)
	var first_mesh: MeshInstance3D = first.get_node("Mesh")
	var second_mesh: MeshInstance3D = second.get_node("Mesh")
	second_mesh.material_override = shared
	var hidden := MeshInstance3D.new()
	hidden.mesh = first_mesh.mesh
	hidden.visible = false
	first.add_child(hidden)
	# Presentation 使用内部节点挂模型，检测也必须能遍历到这些外观。
	var pivot := Node3D.new()
	first.add_child(pivot, false, Node.INTERNAL_MODE_BACK)
	var model := MeshInstance3D.new()
	model.mesh = first_mesh.mesh
	pivot.add_child(model)
	await _frames(4)
	_check("orthographic rays find a narrow blocker away from the camera center", _alpha(first_mesh) < 1.0 and _alpha(first_mesh) > 0.25)
	_check("multiple obstacles along the same view are all faded", _alpha(second_mesh) < 1.0)
	await _frames(16)
	_check("the fade reaches the configured opacity", is_equal_approx(_alpha(first_mesh), 0.25) and is_equal_approx(_alpha(second_mesh), 0.25))
	_check("shared materials and unobstructing instances stay unchanged", shared.albedo_color.a == 1.0 and shared.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and _alpha(unrelated.get_node("Mesh")) == 1.0)
	_check("objects behind the player do not fade", behind.get_node("Mesh").get_surface_override_material(0) == null)
	_check("hidden placeholders stay untouched while internal models fade", hidden.get_surface_override_material(0) == null and is_equal_approx(_alpha(model), 0.25))
	_check("textures and other material properties survive duplication", first_mesh.get_active_material(0).roughness == shared.roughness and first_mesh.get_active_material(0).albedo_texture == shared.albedo_texture)
	_check("ORM next passes fade independently without altering the source", is_equal_approx(first_mesh.get_active_material(0).next_pass.albedo_color.a, 0.15) and is_equal_approx(extra_pass.albedo_color.a, 0.6))
	var ray := PhysicsRayQueryParameters3D.create(Vector3(2, 1, 7), Vector3(2, 1, 0.5), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	_check("transparent geometry still blocks real physics rays", not hit.is_empty() and hit.collider == first)
	_check("transparent geometry still blocks body movement", actor.test_move(actor.global_transform, Vector3(0, 0, 5)))
	_check("fade does not disable collisions or hide mesh nodes", first.collision_layer == 1 and first.get_node("CollisionShape3D").disabled == false and first_mesh.visible)
	actor.position.x = -6
	await _frames(4)
	_check("cleared obstruction restores opacity gradually", _alpha(first_mesh) > 0.25 and _alpha(first_mesh) < 1.0)
	await _frames(16)
	_check("surface overrides are restored to their original references", first_mesh.get_surface_override_material(0) == null and second_mesh.material_override == shared)
	actor.position.x = 2
	await _frames(5)
	var paused_alpha := _alpha(first_mesh)
	paused = true
	for frame in 15: await process_frame
	_check("pause freezes an in-progress material fade", is_equal_approx(_alpha(first_mesh), paused_alpha))
	paused = false
	camera.occlusion_enabled = false
	await _frames(2)
	_check("disabling occlusion restores original materials immediately", first_mesh.get_surface_override_material(0) == null and second_mesh.material_override == shared)
	camera.occlusion_enabled = true
	camera.occlusion_fade_seconds = 0.0
	await _frames(2)
	_check("zero duration applies transparency immediately", is_equal_approx(_alpha(first_mesh), 0.25))
	camera.occluded_opacity = 1.0
	await _frames(2)
	_check("opacity one restores a wall already being faded", first_mesh.get_surface_override_material(0) == null)
	camera.occluded_opacity = 0.25
	first.add_to_group("camera_occlusion_ignore")
	await _frames(2)
	_check("opt-out walls keep their appearance without blocking later detection", first_mesh.get_surface_override_material(0) == null and is_equal_approx(_alpha(second_mesh), 0.25))
	first.queue_free()
	second.queue_free()
	await _frames(2)
	var lintel := _box(Vector3(2, 1.57, 4), Vector3(0.8, 0.18, 0.4), shared)
	await _frames(2)
	_check("head-only obstruction is detected", is_equal_approx(_alpha(lintel.get_node("Mesh")), 0.25))
	actor.height = 0.9
	await _frames(2)
	_check("crouching samples the current body height and releases a clear view", lintel.get_node("Mesh").get_surface_override_material(0) == null)
	actor.height = 1.75
	camera.occlusion_mask = 2
	await _frames(2)
	_check("occlusion uses its configured query mask", lintel.get_node("Mesh").get_surface_override_material(0) == null)
	camera.occlusion_mask = 1
	await _frames(2)
	_check("a changed mask resumes ordinary detection", is_equal_approx(_alpha(lintel.get_node("Mesh")), 0.25))
	var other_camera := Camera3D.new()
	world.add_child(other_camera)
	other_camera.make_current()
	await _frames(2)
	_check("an inactive camera releases its material overrides", lintel.get_node("Mesh").get_surface_override_material(0) == null)
	camera.make_current()
	await _frames(2)
	camera.queue_free()
	await process_frame
	_check("camera removal restores surviving environment materials", lintel.get_node("Mesh").get_surface_override_material(0) == null and shared.albedo_color.a == 1.0)
	world.queue_free()
	await process_frame
	print("Camera occlusion: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)


func _box(position: Vector3, dimensions: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = dimensions
	box.material = material
	mesh.mesh = box
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	shape.shape.size = dimensions
	body.add_child(shape)
	world.add_child(body)
	return body


func _alpha(mesh: MeshInstance3D) -> float:
	return mesh.get_active_material(0).albedo_color.a


func _frames(count: int) -> void:
	for frame in count: await physics_frame
	await process_frame


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + label)
