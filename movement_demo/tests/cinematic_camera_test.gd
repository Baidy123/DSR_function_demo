extends SceneTree

const Shot = preload("res://scripts/systems/cinematic/cinematic_shot_3d.gd")
const Presentation = preload("res://scenes/player/presentation_camera.tscn")

var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var world: Node3D


class LeaseSource extends Camera3D:
	var ledger: Dictionary

	func begin_presentation_occlusion(camera: Camera3D) -> bool:
		ledger["begins"] = int(ledger["begins"]) + 1
		if bool(ledger["deny"]) or ledger["owner"] != null:
			return false
		ledger["owner"] = camera
		return true

	func update_presentation_occlusion(camera: Camera3D, _focus: Node3D, _delta: float) -> void:
		if ledger["owner"] == camera:
			ledger["updates"] = int(ledger["updates"]) + 1

	func end_presentation_occlusion(camera: Camera3D) -> void:
		if ledger["owner"] != camera:
			return
		ledger["owner"] = null
		ledger["ends"] = int(ledger["ends"]) + 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _lens_interpolation()
	await _target_view_properties()
	await _large_delta_crosses_every_phase()
	await _zero_duration_phases()
	await _return_uses_latest_unshaken_source_view()
	await _shake_is_deterministic_local_and_enveloped()
	await _occlusion_lease_and_terminal_identity()
	await _malformed_snapshots_reject_cleanly()
	print("CINEMATIC CAMERA: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _lens_interpolation() -> void:
	_new_world()
	var source: Camera3D = _source(Camera3D.PROJECTION_PERSPECTIVE)
	source.fov = 80.0
	source.size = 10.0
	source.h_offset = 0.4
	source.v_offset = -0.2
	source.frustum_offset = Vector2(0.4, -0.2)
	source.near = 0.1
	source.far = 100.0
	var shot: Camera3D = _shot(2.0, 2.0, 2.0)
	shot.global_transform = Transform3D(Basis.from_euler(Vector3(-0.7, 0.6, 0.0)), Vector3(8.0, 5.0, -4.0))
	shot.projection = Camera3D.PROJECTION_PERSPECTIVE
	shot.fov = 40.0
	shot.size = 6.0
	shot.h_offset = -0.4
	shot.v_offset = 0.2
	shot.frustum_offset = Vector2(-0.2, 0.4)
	shot.near = 1.0
	shot.far = 200.0
	var start_transform: Transform3D = source.global_transform
	var target_transform: Transform3D = shot.global_transform
	var camera: Camera3D = _presentation()

	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 41), "Shot starts")
	camera.advance_presentation(1.0)
	check(_transform_near(camera.global_transform, start_transform.interpolate_with(target_transform, 0.5)),
		"Move pose reaches the hand-checked midpoint")
	check(is_equal_approx(camera.size, 8.0) and is_equal_approx(camera.fov, 60.0),
		"Move interpolates size and perspective FOV together")
	check(is_equal_approx(camera.h_offset, 0.0) and is_equal_approx(camera.v_offset, 0.0),
		"Move interpolates horizontal and vertical offsets")
	check(camera.frustum_offset.is_equal_approx(Vector2(0.1, 0.1)),
		"Move interpolates frustum offset")
	check(is_equal_approx(camera.near, 0.55) and is_equal_approx(camera.far, 150.0),
		"Move interpolates near and far clipping planes")
	check(not results.has({"id": 41, "result": &"completed"}), "Move midpoint has not completed")
	await _clear_world()


func _target_view_properties() -> void:
	_new_world()
	var source: Camera3D = _source()
	source.keep_aspect = Camera3D.KEEP_WIDTH
	source.cull_mask = 3
	source.near = 0.1
	source.far = 300.0
	var source_environment := Environment.new()
	var source_attributes := CameraAttributesPractical.new()
	var source_compositor := Compositor.new()
	source.environment = source_environment
	source.attributes = source_attributes
	source.compositor = source_compositor
	var shot: Camera3D = _shot(1.0, 1.0, 1.0)
	shot.projection = Camera3D.PROJECTION_PERSPECTIVE
	shot.keep_aspect = Camera3D.KEEP_HEIGHT
	shot.cull_mask = 9
	var target_environment := Environment.new()
	var target_attributes := CameraAttributesPhysical.new()
	var target_compositor := Compositor.new()
	shot.environment = target_environment
	shot.attributes = target_attributes
	shot.compositor = target_compositor
	shot.near = 0.5
	shot.far = 900.0
	var camera: Camera3D = _presentation()

	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 42), "Projection-changing Shot starts")
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE
		and camera.keep_aspect == Camera3D.KEEP_HEIGHT
		and camera.cull_mask == 9,
		"Target non-interpolable projection settings switch at cut-in")
	check(camera.environment == target_environment
		and camera.attributes == target_attributes
		and camera.compositor == target_compositor,
		"Target environment, attributes, and compositor switch at cut-in")
	camera.advance_presentation(1.0)
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE
		and is_equal_approx(camera.near, 0.5)
		and is_equal_approx(camera.far, 900.0),
		"Hold uses the authored projection and clipping")

	var latest_environment := Environment.new()
	var latest_attributes := CameraAttributesPractical.new()
	var latest_compositor := Compositor.new()
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.keep_aspect = Camera3D.KEEP_WIDTH
	source.cull_mask = 17
	source.near = 0.2
	source.far = 500.0
	source.environment = latest_environment
	source.attributes = latest_attributes
	source.compositor = latest_compositor
	source.size = 14.0
	source.global_position += Vector3(3.0, 0.0, 1.0)
	source.reset_physics_interpolation()
	camera.advance_presentation(2.0)

	check(source.is_current() and not camera.is_presenting(),
		"Projection-changing Shot restores the player camera")
	check(source.projection == Camera3D.PROJECTION_ORTHOGONAL
		and source.keep_aspect == Camera3D.KEEP_WIDTH
		and source.cull_mask == 17
		and is_equal_approx(source.near, 0.2)
		and is_equal_approx(source.far, 500.0)
		and is_equal_approx(source.size, 14.0),
		"Source projection, clipping, mask, and size remain intact")
	check(source.environment == latest_environment
		and source.attributes == latest_attributes
		and source.compositor == latest_compositor,
		"Source environment resources remain intact")
	await _clear_world()


func _large_delta_crosses_every_phase() -> void:
	_new_world()
	var source: Camera3D = _source()
	var shot: Camera3D = _shot(0.25, 0.5, 0.75)
	var camera: Camera3D = _presentation()
	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 43), "Large-delta Shot starts")
	source.global_position += Vector3(4.0, 0.0, -2.0)
	source.size = 18.0
	source.fov = 52.0
	source.reset_physics_interpolation()
	camera.advance_presentation(2.0)
	check(source.is_current() and not camera.is_presenting(),
		"One large delta crosses MOVE, HOLD, and RETURN")
	check(_transform_near(camera.global_transform, source.global_transform)
		and is_equal_approx(camera.size, source.size)
		and is_equal_approx(camera.fov, source.fov),
		"Large-delta completion lands on the refreshed player view")
	check(results == [{"id": 43, "result": &"completed"}],
		"Large-delta completion emits one terminal event with request identity")
	await _clear_world()


func _zero_duration_phases() -> void:
	_new_world()
	var source: Camera3D = _source()
	var shot: Camera3D = _shot(0.0, 0.0, 0.0)
	var camera: Camera3D = _presentation()
	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 44), "Zero-duration Shot starts")
	camera.advance_presentation(0.0)
	check(source.is_current() and not camera.is_presenting()
		and results == [{"id": 44, "result": &"completed"}],
		"Zero-duration phases finish on one explicit zero-delta tick")
	await _clear_world()

	_new_world()
	source = _source()
	shot = _shot(0.0, 1.0, 0.0)
	camera = _presentation()
	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 45), "Mixed zero-duration Shot starts")
	camera.advance_presentation(0.0)
	check(camera.is_current() and _transform_near(camera.global_transform, shot.global_transform),
		"Zero MOVE advances directly to the HOLD pose")
	camera.advance_presentation(1.0)
	check(source.is_current() and results == [{"id": 45, "result": &"completed"}],
		"Zero RETURN completes immediately after HOLD")
	await _clear_world()


func _return_uses_latest_unshaken_source_view() -> void:
	_new_world()
	var source: Camera3D = _source(Camera3D.PROJECTION_PERSPECTIVE)
	source.fov = 70.0
	var shot: Camera3D = _shot(1.0, 1.0, 2.0)
	shot.transition_easing = Shot.Easing.LINEAR
	shot.projection = Camera3D.PROJECTION_PERSPECTIVE
	shot.fov = 35.0
	shot.size = 7.0
	var camera: Camera3D = _presentation()
	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 46), "Return-refresh Shot starts")
	camera.advance_presentation(1.0)
	check(_transform_near(camera.global_transform, shot.global_transform)
		and is_equal_approx(camera.size, 7.0)
		and is_equal_approx(camera.fov, 35.0),
		"Return starts from the unshaken authored HOLD view")

	source.global_position = Vector3(12.0, 9.0, -7.0)
	source.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	source.size = 15.0
	source.fov = 75.0
	source.reset_physics_interpolation()
	camera.advance_presentation(1.0)
	camera.advance_presentation(1.0)
	check(_transform_near(camera.global_transform, shot.global_transform.interpolate_with(source.global_transform, 0.5))
		and is_equal_approx(camera.size, 11.0)
		and is_equal_approx(camera.fov, 55.0),
		"Return midpoint uses the latest source pose and size")

	source.global_position += Vector3(-2.0, 1.0, 3.0)
	source.size = 19.0
	source.fov = 61.0
	source.reset_physics_interpolation()
	camera.advance_presentation(0.5)
	check(_transform_near(camera.global_transform, shot.global_transform.interpolate_with(source.global_transform, 0.75))
		and is_equal_approx(camera.size, 16.0)
		and is_equal_approx(camera.fov, 54.5),
		"Ongoing RETURN re-reads changes instead of freezing its old destination")
	camera.advance_presentation(0.5)
	check(source.is_current() and _transform_near(camera.global_transform, source.global_transform)
		and is_equal_approx(camera.size, 19.0)
		and is_equal_approx(camera.fov, 61.0),
		"Return ends on the latest player pose and lens")
	await _clear_world()


func _shake_is_deterministic_local_and_enveloped() -> void:
	_new_world()
	var source: Camera3D = _source(Camera3D.PROJECTION_PERSPECTIVE)
	source.fov = 68.0
	var shot: Camera3D = _shot(1.0, 1.0, 1.0)
	shot.transition_easing = Shot.Easing.LINEAR
	shot.projection = Camera3D.PROJECTION_PERSPECTIVE
	shot.global_transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-37.0), deg_to_rad(63.0), deg_to_rad(11.0))),
		Vector3(7.0, 4.0, -3.0))
	shot.shake_enabled = true
	shot.shake_position_amplitude = Vector3(0.2, 0.1, 0.3)
	shot.shake_rotation_degrees = Vector3(7.0, 11.0, 5.0)
	shot.shake_frequency = 4.0
	shot.shake_fade_in_seconds = 0.5
	shot.shake_fade_out_seconds = 0.5
	shot.shake_seed = 123
	var snapshot: Dictionary = shot.runtime_snapshot()
	var source_transform: Transform3D = source.global_transform
	var shot_transform: Transform3D = shot.global_transform
	var camera: Camera3D = _presentation()

	check(camera.start_cinematic_shot(source, snapshot, 47), "Shake Shot starts")
	camera.advance_presentation(0.25)
	check(is_equal_approx(float(camera.call("_shake_envelope")), 0.5),
		"MOVE shake envelope fades in once")
	camera.advance_presentation(0.75)
	check(is_equal_approx(float(camera.call("_shake_envelope")), 1.0),
		"HOLD starts at full shake amplitude instead of fading in again")
	camera.advance_presentation(0.4)
	var first_shaken: Transform3D = camera.global_transform
	check(_transform_near(first_shaken, _expected_shaken_transform(shot_transform, 1.4, 123, 4.0,
		Vector3(0.2, 0.1, 0.3), Vector3(7.0, 11.0, 5.0)), 0.0002),
		"Shake is deterministically added in the base Shot local basis")
	check(_transform_near(source.global_transform, source_transform)
		and is_equal_approx(source.fov, 68.0)
		and _transform_near(shot.global_transform, shot_transform)
		and snapshot["transform"] == shot_transform,
		"Shake does not mutate the source camera or Shot")

	camera.cancel_presentation()
	check(camera.start_cinematic_shot(source, snapshot, 48), "Same-seed shake Shot restarts")
	camera.advance_presentation(1.0)
	camera.advance_presentation(0.4)
	check(_transform_near(camera.global_transform, first_shaken, 0.0002),
		"Same seed and phase time produce identical local shake")

	camera.advance_presentation(0.6)
	check(_transform_near(camera.get("_return_from") as Transform3D, shot_transform),
		"RETURN stores the unshaken HOLD transform")
	check(is_equal_approx(float(camera.call("_shake_envelope")), 1.0),
		"RETURN starts its fade-out from full amplitude")
	camera.advance_presentation(0.25)
	check(is_equal_approx(float(camera.call("_shake_envelope")), 0.5),
		"RETURN shake envelope fades toward zero")
	camera.advance_presentation(0.75)
	check(source.is_current() and _transform_near(source.global_transform, source_transform),
		"Shaken Shot returns to the untouched source camera")
	await _clear_world()


func _expected_shaken_transform(base: Transform3D, elapsed: float, seed_value: int,
		frequency: float, position_amplitude: Vector3, rotation_degrees_amplitude: Vector3) -> Transform3D:
	var position_noise := FastNoiseLite.new()
	position_noise.seed = seed_value
	var rotation_noise := FastNoiseLite.new()
	rotation_noise.seed = seed_value
	var phase: float = elapsed * frequency
	var local_position := Vector3(
		position_noise.get_noise_1d(phase),
		position_noise.get_noise_1d(phase + 31.0),
		position_noise.get_noise_1d(phase + 67.0))
	var local_rotation_degrees := Vector3(
		rotation_noise.get_noise_1d(phase + 13.0),
		rotation_noise.get_noise_1d(phase + 47.0),
		rotation_noise.get_noise_1d(phase + 89.0)) * rotation_degrees_amplitude
	var local_rotation := Basis.from_euler(Vector3(
		deg_to_rad(local_rotation_degrees.x),
		deg_to_rad(local_rotation_degrees.y),
		deg_to_rad(local_rotation_degrees.z)))
	return Transform3D(
		base.basis * local_rotation,
		base.origin + base.basis * (local_position * position_amplitude))


func _occlusion_lease_and_terminal_identity() -> void:
	_new_world()
	var ledger := {"owner": null, "begins": 0, "updates": 0, "ends": 0, "deny": false}
	var source: Camera3D = _lease_source(ledger)
	var shot: Camera3D = _shot(1.0, 1.0, 1.0)
	var camera: Camera3D = _presentation()
	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 50), "Lease Shot starts")
	check(ledger["owner"] == camera and int(ledger["begins"]) == 1,
		"Cinematic cut-in acquires the source occlusion handoff")
	camera.advance_presentation(0.25)
	check(int(ledger["updates"]) > 0,
		"Cinematic camera updates the acquired source occlusion lease")
	camera.cancel_presentation()
	check(source.is_current() and not camera.is_presenting()
		and ledger["owner"] == null and int(ledger["ends"]) == 1,
		"Cinematic cancellation restores and releases the source lease")
	check(results == [{"id": 50, "result": &"cancelled"}],
		"Cinematic cancellation emits one terminal event with request identity")
	camera.cancel_presentation()
	camera.advance_presentation(100.0)
	check(results.size() == 1 and int(ledger["ends"]) == 1,
		"Repeated cancellation cannot duplicate terminal cleanup")

	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 51), "Source-loss Shot starts")
	camera.advance_presentation(0.1)
	source.queue_free()
	await process_frame
	check(ledger["owner"] == null and int(ledger["ends"]) == 2,
		"Source loss releases the occlusion handoff")
	check(results.back() == {"id": 51, "result": &"source_lost"} and not camera.is_presenting(),
		"Source loss emits one matching terminal event")

	var denied_ledger := {"owner": null, "begins": 0, "updates": 0, "ends": 0, "deny": true}
	var denied_source: Camera3D = _lease_source(denied_ledger)
	check(not camera.start_cinematic_shot(denied_source, shot.runtime_snapshot(), 52)
		and denied_source.is_current() and not camera.is_presenting()
		and denied_ledger["owner"] == null,
		"Lease denial rejects before camera ownership changes")

	var completion_ledger := {"owner": null, "begins": 0, "updates": 0, "ends": 0, "deny": false}
	var completion_source: Camera3D = _lease_source(completion_ledger)
	var instant_shot: Camera3D = _shot(0.0, 0.0, 0.0)
	check(camera.start_cinematic_shot(completion_source, instant_shot.runtime_snapshot(), 53),
		"Lease completion Shot starts")
	camera.advance_presentation(0.0)
	check(completion_source.is_current()
		and completion_ledger["owner"] == null
		and int(completion_ledger["ends"]) == 1
		and results.back() == {"id": 53, "result": &"completed"},
		"Terminal completion releases the source lease")
	await _clear_world()


func _lease_source(ledger: Dictionary) -> Camera3D:
	var source := LeaseSource.new()
	source.ledger = ledger
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	source.position = Vector3(0.0, 8.0, 6.0)
	source.rotation_degrees.x = -55.0
	source.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(source)
	source.make_current()
	source.reset_physics_interpolation()
	return source


func _malformed_snapshots_reject_cleanly() -> void:
	_new_world()
	var ledger := {"owner": null, "begins": 0, "updates": 0, "ends": 0, "deny": false}
	var source: Camera3D = _lease_source(ledger)
	var shot: Camera3D = _shot(1.0, 1.0, 1.0)
	var valid: Dictionary = shot.runtime_snapshot()
	var camera: Camera3D = _presentation()

	check(not camera.start_cinematic_shot(source, {}, 60)
		and source.is_current() and not camera.is_presenting()
		and ledger["owner"] == null and int(ledger["begins"]) == 0,
		"Missing transform snapshot rejects before ownership")

	var bad_transform: Dictionary = valid.duplicate(true)
	bad_transform["transform"] = "not a transform"
	check(not camera.start_cinematic_shot(source, bad_transform, 61)
		and source.is_current() and not camera.is_presenting()
		and ledger["owner"] == null and int(ledger["begins"]) == 0,
		"Malformed transform rejects before ownership")

	var bad_timing: Dictionary = valid.duplicate(true)
	bad_timing["enter_seconds"] = NAN
	check(not camera.start_cinematic_shot(source, bad_timing, 62)
		and source.is_current() and not camera.is_presenting()
		and ledger["owner"] == null and int(ledger["begins"]) == 0,
		"Non-finite timing rejects before ownership")

	var bad_projection: Dictionary = valid.duplicate(true)
	bad_projection["projection"] = 99
	check(not camera.start_cinematic_shot(source, bad_projection, 63)
		and source.is_current() and not camera.is_presenting()
		and ledger["owner"] == null and int(ledger["begins"]) == 0,
		"Invalid projection enum rejects before ownership")

	var bad_environment: Dictionary = valid.duplicate(true)
	bad_environment["environment"] = "not an environment"
	check(not camera.start_cinematic_shot(source, bad_environment, 64)
		and source.is_current() and not camera.is_presenting()
		and ledger["owner"] == null and int(ledger["begins"]) == 0,
		"Wrong environment resource type rejects before ownership")

	var bad_shake: Dictionary = valid.duplicate(true)
	bad_shake["shake_position_amplitude"] = Vector3(NAN, 0.0, 0.0)
	check(not camera.start_cinematic_shot(source, bad_shake, 65)
		and source.is_current() and not camera.is_presenting()
		and ledger["owner"] == null and int(ledger["begins"]) == 0,
		"Non-finite shake configuration rejects before ownership")
	await _clear_world()


func _new_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	results.clear()


func _source(projection_mode: int = Camera3D.PROJECTION_ORTHOGONAL) -> Camera3D:
	var source: Camera3D = Camera3D.new()
	source.projection = projection_mode
	source.size = 12.0
	source.fov = 75.0
	source.position = Vector3(0.0, 8.0, 6.0)
	source.rotation_degrees.x = -55.0
	source.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(source)
	source.make_current()
	source.reset_physics_interpolation()
	return source


func _shot(enter_seconds: float, hold_seconds: float, return_seconds: float) -> Camera3D:
	var shot: Camera3D = Shot.new()
	shot.position = Vector3(8.0, 5.0, -4.0)
	shot.rotation_degrees = Vector3(-48.0, 25.0, 0.0)
	shot.size = 6.0
	shot.fov = 40.0
	shot.enter_seconds = enter_seconds
	shot.hold_seconds = hold_seconds
	shot.return_seconds = return_seconds
	world.add_child(shot)
	return shot


func _presentation() -> Camera3D:
	var camera: Camera3D = Presentation.instantiate()
	world.add_child(camera)
	camera.presentation_finished.connect(_finished)
	return camera


func _finished(request_id: int, result: StringName) -> void:
	results.append({"id": request_id, "result": result})


func _clear_world() -> void:
	paused = false
	world.queue_free()
	await process_frame
	await process_frame
	world = null


func _transform_near(left: Transform3D, right: Transform3D, epsilon: float = 0.0001) -> bool:
	return left.origin.distance_to(right.origin) <= epsilon \
		and left.basis.x.distance_to(right.basis.x) <= epsilon \
		and left.basis.y.distance_to(right.basis.y) <= epsilon \
		and left.basis.z.distance_to(right.basis.z) <= epsilon


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1
