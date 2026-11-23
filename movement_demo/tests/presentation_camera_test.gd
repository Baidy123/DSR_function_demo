extends SceneTree

const PresentationScene: PackedScene = preload("res://scenes/player/presentation_camera.tscn")
const PlayerCamera = preload("res://scripts/systems/player_camera.gd")
const CameraRig: PackedScene = preload("res://scenes/player/player_camera_rig.tscn")

var checks: int = 0
var failures: int = 0
var results: Array[Dictionary] = []
var world: Node3D

class Actor extends Node3D:
	var ground_height: float = 0.0
	var velocity: Vector3 = Vector3.ZERO
	func _physics_process(delta: float) -> void:
		position += velocity * delta
	func get_camera_ground_height() -> float:
		return ground_height
	func get_body_height() -> float:
		return 1.75

class Combat extends Node:
	signal weapon_changed(data: WeaponData)
	var weapon: WeaponData


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _copy_and_timing()
	await _cancellation_and_lifecycle()
	await _fallback_projection()
	await _paused_rig_return()
	await _occlusion_handoff()
	if "--capture" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			_check("capture requires a real renderer", false)
		else:
			await _rendered_handoff()
			await _rendered_paused_rig()
	print("Presentation camera: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _new_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	results.clear()


func _clear_world() -> void:
	paused = false
	world.queue_free()
	await process_frame
	await process_frame


func _actor() -> Actor:
	var actor: Actor = Actor.new()
	actor.name = "Player"
	world.add_child(actor)
	return actor


func _source() -> Camera3D:
	var camera: Camera3D = PlayerCamera.new()
	camera.position = Vector3(0.3, 7.0, 5.0)
	camera.rotation_degrees.x = -55.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(camera)
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.make_current()
	camera.reset_physics_interpolation()
	return camera


func _presentation() -> Camera3D:
	var camera: Camera3D = PresentationScene.instantiate() as Camera3D
	world.add_child(camera)
	camera.connect("presentation_finished", _finished)
	return camera


func _finished(request_id: int, result: StringName) -> void:
	results.append({"id": request_id, "result": result})


func _copy_and_timing() -> void:
	_new_world()
	var actor: Actor = _actor()
	actor.position = Vector3(2.0, 3.0, 1.0)
	actor.ground_height = 0.0
	actor.reset_physics_interpolation()
	var source: Camera3D = _source()
	source.near = 0.17
	source.far = 450.0
	source.fov = 64.0
	source.keep_aspect = Camera3D.KEEP_WIDTH
	source.h_offset = 0.2
	source.v_offset = -0.15
	source.frustum_offset = Vector2(0.12, -0.08)
	source.cull_mask = 13
	source.environment = Environment.new()
	source.attributes = CameraAttributesPractical.new()
	source.compositor = Compositor.new()
	var presentation: Camera3D = _presentation()
	_check("scene is inactive and has no automatic tick", not presentation.is_current() and not presentation.is_processing() and not presentation.is_physics_processing())
	var original: Transform3D = source.global_transform
	var focus: Vector3 = Vector3(10.0, 0.0, -5.0)
	var options: Dictionary = {"move_seconds": 2.0, "hold_seconds": 1.0, "return_seconds": 2.0, "size": 8.0}
	_check("current source accepts a presentation", presentation.start_presentation(source, focus, options, 7))
	_check("switch happens after source pose is copied", root.get_camera_3d() == presentation and presentation.global_transform.is_equal_approx(original))
	_check("projection and lens match before moving", presentation.projection == source.projection and presentation.keep_aspect == source.keep_aspect and is_equal_approx(presentation.size, 12.0) and is_equal_approx(presentation.fov, 64.0))
	_check("clipping and offsets are copied", is_equal_approx(presentation.near, 0.17) and is_equal_approx(presentation.far, 450.0) and presentation.cull_mask == 13 and is_equal_approx(presentation.h_offset, 0.2) and is_equal_approx(presentation.v_offset, -0.15) and presentation.frustum_offset.is_equal_approx(source.frustum_offset))
	_check("environment attributes and compositor are borrowed read-only", presentation.environment == source.environment and presentation.attributes == source.attributes and presentation.compositor == source.compositor)
	_check("projected ground and actor positions match on switch", presentation.unproject_position(focus).distance_to(source.unproject_position(focus)) < 0.01 and presentation.unproject_position(actor.global_position).distance_to(source.unproject_position(actor.global_position)) < 0.01)
	await process_frame
	await process_frame
	_check("elapsed frames cannot advance the owner-driven camera", presentation.global_transform.is_equal_approx(original) and presentation.is_presenting())
	_check("busy component rejects a second request", not presentation.start_presentation(source, focus, options, 8))
	presentation.advance_presentation(1.0)
	var destination: Vector3 = original.origin + focus - Vector3(2.0, 0.0, 1.0)
	_check("move has a real midpoint and keeps ground focus offset despite vault height", presentation.global_position.is_equal_approx(original.origin.lerp(destination, 0.5)) and is_equal_approx(presentation.size, 10.0))
	_check("move preserves source rig pose and follows no actor", source.global_transform.is_equal_approx(original) and source.get_follow_actor() == actor and presentation.global_basis.is_equal_approx(source.global_basis))
	presentation.advance_presentation(1.5)
	_check("move remainder reaches hold without finishing early", presentation.is_presenting() and presentation.global_position.is_equal_approx(destination) and is_equal_approx(presentation.size, 8.0) and results.is_empty())
	source.global_position += Vector3(-3.0, 0.0, 2.0)
	source.size = 15.0
	source.reset_physics_interpolation()
	presentation.advance_presentation(1.5)
	_check("return moves toward the latest source view", presentation.global_position.is_equal_approx(destination.lerp(source.global_position, 0.5)) and is_equal_approx(presentation.size, 11.5) and presentation.is_current())
	source.global_position += Vector3(1.0, 0.0, 1.0)
	source.size = 16.0
	source.reset_physics_interpolation()
	presentation.advance_presentation(1.0)
	_check("return aligns both pose and lens before restoring current camera", source.is_current() and presentation.global_transform.is_equal_approx(source.global_transform) and is_equal_approx(presentation.size, 16.0))
	_check("completion is emitted once with the request identity", not presentation.is_presenting() and results == [{"id": 7, "result": &"completed"}])
	presentation.advance_presentation(100.0)
	presentation.cancel_presentation()
	_check("finish and cancellation are idempotent", results.size() == 1)
	_check("options and source resources were not mutated", options.size == 8.0 and source.environment == presentation.environment and source.attributes == presentation.attributes)
	await _clear_world()


func _cancellation_and_lifecycle() -> void:
	_new_world()
	_actor()
	var source: Camera3D = _source()
	var presentation: Camera3D = _presentation()
	var outsider: Camera3D = Camera3D.new()
	world.add_child(outsider)
	_check("noncurrent source cannot steal viewport ownership", not presentation.start_presentation(outsider, Vector3.ZERO, {}, 10) and source.is_current())
	var other_view: SubViewport = SubViewport.new()
	world.add_child(other_view)
	var other_camera: Camera3D = Camera3D.new()
	other_view.add_child(other_camera)
	_check("different viewport and nonfinite focus are rejected", not presentation.start_presentation(other_camera, Vector3.ZERO, {}, 11) and not presentation.start_presentation(source, Vector3(INF, 0, 0), {}, 12))
	presentation.start_presentation(source, Vector3(8, 0, 0), {}, 13)
	presentation.advance_presentation(0.3)
	presentation.cancel_presentation()
	_check("cancel restores a valid source and releases its occlusion lease", source.is_current() and not presentation.is_presenting() and source.get("_presentation_occlusion_owner") == null and results.back().result == &"cancelled")
	presentation.start_presentation(source, Vector3(8, 0, 0), {}, 14)
	outsider.make_current()
	presentation.cancel_presentation()
	_check("cancel cannot take current camera back from another owner", outsider.is_current() and source.get("_presentation_occlusion_owner") == null)
	source.make_current()
	presentation.start_presentation(source, Vector3(8, 0, 0), {}, 15)
	outsider.make_current()
	presentation.advance_presentation(3.0)
	_check("normal tick also respects a replacement camera", outsider.is_current() and results.back().result == &"camera_lost" and not presentation.is_presenting())
	source.make_current()
	presentation.start_presentation(source, Vector3(8, 0, 0), {}, 16)
	presentation.cancel_presentation(false)
	_check("unload cancellation does not choose an arbitrary camera", root.get_camera_3d() == null and not presentation.is_presenting())
	source.make_current()
	presentation.start_presentation(source, Vector3.ZERO, {"move_seconds": 0.0, "hold_seconds": 0.0, "return_seconds": 0.0, "size": -5.0}, 17)
	presentation.advance_presentation(NAN)
	_check("invalid delta cannot poison or advance the state", presentation.is_presenting() and presentation.global_position.is_finite())
	presentation.advance_presentation(0.0)
	_check("zero-duration phases finish on an explicit tick and nonpositive size preserves source", source.is_current() and results.back().result == &"completed" and is_equal_approx(presentation.size, source.size))
	presentation.start_presentation(source, Vector3.ZERO, {}, 18)
	source.queue_free()
	await process_frame
	_check("source destruction cancels without stale reference access", not presentation.is_presenting() and results.back().result == &"source_lost")
	source = _source()
	presentation.start_presentation(source, Vector3.ZERO, {}, 19)
	presentation.queue_free()
	await process_frame
	_check("component destruction restores a surviving source and its material writer", source.is_current() and source.get("_presentation_occlusion_owner") == null)
	presentation = _presentation()
	presentation.start_presentation(source, Vector3.ZERO, {}, 20)
	await _clear_world()
	_check("whole-tree teardown emits one terminal event", results.back().id == 20 and results.back().result in [&"source_lost", &"cancelled"])


func _fallback_projection() -> void:
	_new_world()
	var source: Camera3D = Camera3D.new()
	source.position = Vector3(1.0, 8.0, 6.0)
	source.rotation_degrees.x = -55.0
	source.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(source)
	source.make_current()
	var presentation: Camera3D = _presentation()
	for mode: int in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL, Camera3D.PROJECTION_FRUSTUM]:
		source.projection = mode
		source.h_offset = 0.35
		source.v_offset = 0.12
		source.frustum_offset = Vector2(0.15, 0.07)
		var focus: Vector3 = Vector3(-6.0, 2.0, -5.0)
		_check("unbound view-ground ray supports projection %d" % mode, presentation.start_presentation(source, focus, {"move_seconds": 1.0, "hold_seconds": 1.0}, 30 + mode))
		presentation.advance_presentation(1.0)
		var center: Vector2 = root.get_visible_rect().size * 0.5
		_check("unbound focus is centered with offsets for projection %d" % mode, presentation.unproject_position(focus).distance_to(center) < 0.02)
		presentation.cancel_presentation()
	source.rotation = Vector3.ZERO
	_check("a ray parallel to the ground rejects ambiguous framing", not presentation.start_presentation(source, Vector3.ZERO, {}, 34) and source.is_current())
	await _clear_world()


func _paused_rig_return() -> void:
	_new_world()
	var actor: Actor = _actor()
	var combat: Combat = Combat.new()
	combat.name = "Combat"
	combat.weapon = WeaponData.new()
	combat.weapon.aim_range = 18.0
	actor.add_child(combat)
	var source: Camera3D = CameraRig.instantiate() as Camera3D
	world.add_child(source)
	await process_frame
	await process_frame
	var phantom: Node = source.get_node("PhantomCamera3D")
	var anchor: Node3D = source.get_node("CameraGroundAnchor")
	var follow_target: Node3D = phantom.get("follow_target") as Node3D
	var offset: Vector3 = phantom.get("follow_offset")
	var initial_size: float = source.size
	var presentation: Camera3D = _presentation()
	paused = true
	_check("a paused source can hand off without resuming the tree", presentation.start_presentation(source, Vector3(12, 0, 4), {"move_seconds": 0.5, "hold_seconds": 0.5, "return_seconds": 1.0}, 40) and paused)
	actor.position = Vector3(5.0, 3.0, -2.0)
	actor.ground_height = 0.5
	actor.reset_physics_interpolation()
	var next_weapon: WeaponData = WeaponData.new()
	next_weapon.aim_range = 28.0
	combat.weapon = next_weapon
	combat.weapon_changed.emit(next_weapon)
	presentation.advance_presentation(1.5)
	_check("paused return refreshes ground anchor and Phantom host without combat", anchor.global_position.is_equal_approx(Vector3(5.0, 0.5, -2.0)) and source.global_position.is_equal_approx(anchor.global_position + offset) and paused)
	_check("paused return resolves the latest weapon view", source.size > initial_size and is_equal_approx(source.size, float(source.call("_size_for_lock_range", 28.0))))
	actor.position.x += 2.0
	actor.reset_physics_interpolation()
	presentation.advance_presentation(0.5)
	_check("return tracks changes during its own animation and restores the refreshed camera", source.is_current() and presentation.global_transform.is_equal_approx(source.global_transform) and is_equal_approx(source.global_position.x, actor.position.x + offset.x))
	_check("rig target offset paths and pause remain intact", phantom.get("follow_target") == follow_target and follow_target == anchor and phantom.get("follow_offset") == offset and paused)
	paused = false
	await physics_frame
	await process_frame
	_check("resuming cannot replay an unfinished source entrance tween", source.global_position.is_equal_approx(anchor.global_position + offset) and not bool(source.get_node("PhantomCameraHost").call("get_trigger_pcam_tween")))
	await _clear_world()


func _occlusion_handoff() -> void:
	_new_world()
	_actor()
	var source: Camera3D = _source()
	source.position = Vector3(0, 1, 8)
	source.rotation = Vector3.ZERO
	source.set("occlusion_fade_seconds", 0.0)
	source.reset_physics_interpolation()
	var shared: StandardMaterial3D = StandardMaterial3D.new()
	shared.albedo_color = Color(0.2, 0.5, 0.8, 1.0)
	var player_blocker: MeshInstance3D = _box(Vector3(0, 1, 4), Vector3(1.5, 2, 0.5), shared)
	var focus_blocker: MeshInstance3D = _box(Vector3(8, 1, 4), Vector3(1.5, 2, 0.5), shared)
	player_blocker.add_to_group("camera_fadeable")
	focus_blocker.add_to_group("camera_fadeable")
	source.call("_physics_process", 0.1)
	var original_clone: Material = player_blocker.get_surface_override_material(0)
	_check("fixture starts with the source owning a faded material clone", original_clone != null and original_clone != shared)
	var presentation: Camera3D = _presentation()
	paused = true
	presentation.start_presentation(source, Vector3(8, 0, 0), {"move_seconds": 1.0, "hold_seconds": 1.0, "return_seconds": 1.0}, 50)
	_check("handoff preserves source appearance until the first movement tick", player_blocker.get_surface_override_material(0) == original_clone)
	presentation.advance_presentation(1.0)
	_check("the single writer restores old blockers and fades presentation-target blockers", player_blocker.get_surface_override_material(0) == null and focus_blocker.get_surface_override_material(0) != null)
	source.call("_physics_process", 0.1)
	_check("inactive source tick cannot clear the presentation's fade", focus_blocker.get_surface_override_material(0) != null)
	presentation.cancel_presentation()
	_check("paused cancel restores player occlusion immediately and clears target occlusion", player_blocker.get_surface_override_material(0) != null and focus_blocker.get_surface_override_material(0) == null)
	_check("shared material alpha and render mode never change", shared.albedo_color.a == 1.0 and shared.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	presentation.start_presentation(source, Vector3(8, 0, 0), {"move_seconds": 0.0, "hold_seconds": 1.0}, 51)
	presentation.advance_presentation(0.0)
	var replacement: StandardMaterial3D = StandardMaterial3D.new()
	focus_blocker.set_surface_override_material(0, replacement)
	var outsider: Camera3D = Camera3D.new()
	world.add_child(outsider)
	outsider.make_current()
	presentation.cancel_presentation()
	_check("third-party camera and material ownership survive old-request cleanup", outsider.is_current() and focus_blocker.get_surface_override_material(0) == replacement and player_blocker.get_surface_override_material(0) == null)
	source.make_current()
	presentation.start_presentation(source, Vector3(8, 0, 0), {"move_seconds": 0.0, "hold_seconds": 0.0, "return_seconds": 1.0}, 52)
	world.get_node("Player").queue_free()
	await process_frame
	presentation.advance_presentation(1.0)
	_check("loss of follow actor during return leaves a finite valid source view", source.is_current() and not presentation.is_presenting() and presentation.global_position.is_finite())
	await _clear_world()


func _box(at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = dimensions
	box.material = material
	mesh.mesh = box
	mesh.position = at
	world.add_child(mesh)
	return mesh


func _rendered_handoff() -> void:
	_new_world()
	_actor()
	var source: Camera3D = _source()
	source.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.08, 0.13)
	source.environment = environment
	for index in 7:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color.from_hsv(float(index) / 7.0, 0.65, 0.85)
		_box(Vector3(float(index - 3) * 2.0, 0.7, -float(index % 3) * 2.0), Vector3(1.1, 1.4, 1.1), material)
	var presentation: Camera3D = _presentation()
	var before: Image = await _frame_image()
	presentation.start_presentation(source, Vector3(7, 0, -3), {"move_seconds": 1.0, "hold_seconds": 1.0, "return_seconds": 1.0, "size": 9.0}, 60)
	var switched: Image = await _frame_image()
	_check("rendered cut-in preserves actual pixels", _difference(before, switched) < 0.003)
	presentation.advance_presentation(1.0)
	var focused: Image = await _frame_image()
	_check("rendered movement changes the visible composition", _difference(switched, focused) > 0.01)
	presentation.advance_presentation(1.99999)
	var aligned: Image = await _frame_image()
	presentation.advance_presentation(0.00002)
	var restored: Image = await _frame_image()
	_check("rendered final handoff preserves the aligned view", _difference(aligned, restored) < 0.003 and source.is_current())
	_check("rendered return matches the original view", _difference(before, restored) < 0.003)
	var directory: String = "res://logs/presentation_camera"
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	var captures: Dictionary = {"source": before, "switched": switched, "focused": focused, "aligned": aligned, "returned": restored}
	for label: String in captures:
		var capture: Image = captures[label]
		if capture.save_png(directory.path_join(label + ".png")) != OK: error = FAILED
	_check("five real-render captures were saved", error == OK)
	await _clear_world()


func _frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _rendered_paused_rig() -> void:
	_new_world()
	var actor: Actor = _actor()
	var source: Camera3D = CameraRig.instantiate() as Camera3D
	world.add_child(source)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.08, 0.13)
	source.environment = environment
	for index in 9:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color.from_hsv(float(index) / 9.0, 0.7, 0.9)
		_box(Vector3(float(index - 4) * 2.0, 0.7, -float(index % 3) * 2.0), Vector3(1.1, 1.4, 1.1), material)
	var presentation: Camera3D = _presentation()
	actor.velocity = Vector3(1.5, 0.0, 0.0)
	# Exercise the actual physics-interpolated ground anchor / Phantom host chain.
	for frame in 75: await physics_frame
	var before: Image = await _frame_image()
	paused = true
	presentation.start_presentation(source, Vector3(7, 0, -3), {"move_seconds": 1.0, "hold_seconds": 1.0, "return_seconds": 1.0}, 70)
	var switched: Image = await _frame_image()
	_check("moving interpolated rig cuts into the same rendered frame", _difference(before, switched) < 0.003)
	presentation.advance_presentation(1.0)
	actor.position += Vector3(4.0, 0.0, -2.0)
	actor.velocity = Vector3.ZERO
	actor.reset_physics_interpolation()
	presentation.advance_presentation(1.99999)
	var aligned: Image = await _frame_image()
	presentation.advance_presentation(0.00002)
	var restored: Image = await _frame_image()
	_check("paused rig return cuts between matching rendered views", _difference(aligned, restored) < 0.003)
	paused = false
	for frame in 3: await physics_frame
	var resumed: Image = await _frame_image()
	_check("resuming actual rig has no old-position snap", _difference(restored, resumed) < 0.003)
	var directory: String = "res://logs/presentation_camera"
	var captures: Dictionary = {"rig_source": before, "rig_switched": switched, "rig_aligned": aligned, "rig_returned": restored, "rig_resumed": resumed}
	var error: Error = OK
	for label: String in captures:
		var capture: Image = captures[label]
		if capture.save_png(directory.path_join(label + ".png")) != OK: error = FAILED
	_check("moving and paused rig captures were saved", error == OK)
	await _clear_world()


func _difference(first: Image, second: Image) -> float:
	if first.get_size() != second.get_size() or first.is_empty(): return INF
	var total: float = 0.0
	var samples: int = 0
	for y in range(0, first.get_height(), 4):
		for x in range(0, first.get_width(), 4):
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 3
	return total / float(samples)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failures += 1
	print(("PASS " if passed else "FAIL ") + label)
