extends SceneTree

var checks := 0
var failed := 0

class ReticleTarget extends Node3D:
	var elapsed := 0.0
	var origin := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		elapsed += delta
		global_position = origin + Vector3(2.0 * sin(elapsed * 3.0), 0.0, 0.0)
		rotation.y = elapsed

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene = packed.instantiate()
	var actor = scene.get_node("Player")
	var slots = actor.get_node("Equipment")
	var combat = actor.get_node("Combat")
	var camera = scene.get_node("Camera3D")
	var base_size: float = camera.size
	var pistol: WeaponData = slots.primary_weapon.duplicate()
	var rifle: WeaponData = slots.secondary_weapon.duplicate()
	# 保留手动Size模式的原合同；范围联动另由 combat_view_test 验证。
	pistol.camera_follows_aim_range = false
	rifle.camera_follows_aim_range = false
	pistol.camera_view_size = 13.0
	pistol.camera_transition_seconds = 0.3
	rifle.camera_view_size = 17.0
	rifle.camera_transition_seconds = 0.3
	slots.primary_weapon = pistol
	slots.secondary_weapon = rifle
	slots.starting_slot = 1
	root.add_child(scene)
	current_scene = scene
	actor.set_physics_process(false)
	_check("birth reads already-equipped secondary weapon without an opening zoom", is_equal_approx(camera.size, 17.0))
	_check("existing camera host and ground anchor remain connected", camera.has_node("PhantomCameraHost") and camera.get_node("PhantomCamera3D").follow_target == camera.get_node("CameraGroundAnchor"))
	_check("camera projection stays orthogonal", camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	_check("third-party camera only follows the transform without a competing lens override", camera.get_node("PhantomCamera3D").camera_3d_resource == null)
	var follow_offset: Vector3 = camera.get_node("PhantomCamera3D").follow_offset
	await _frames(3)
	_key(KEY_1)
	_check("real slot input changes weapon without snapping the camera", combat.weapon == pistol and is_equal_approx(camera.size, 17.0))
	await _frames(6)
	_check("weapon-specific duration produces an intermediate view", camera.size > 13.0 and camera.size < 17.0)
	var before_pause: float = camera.size
	paused = true
	for frame in 20: await process_frame
	_check("pausing freezes the camera transition", is_equal_approx(camera.size, before_pause))
	paused = false
	var before_switch: float = camera.size
	_key(KEY_2)
	_check("switching again mid-transition starts from the current view", is_equal_approx(camera.size, before_switch))
	await _frames(24)
	_check("rifle finishes at the wider view", is_equal_approx(camera.size, 17.0))
	_key(KEY_1)
	await _frames(24)
	_check("switching back restores the pistol view", is_equal_approx(camera.size, 13.0))
	_check("weapon view does not change camera tilt or follow offset", camera.get_node("PhantomCamera3D").follow_offset == follow_offset)
	var fire_range: float = pistol.fire_range
	var aim_range: float = pistol.aim_range
	var magazine: int = combat.ammo.magazine_rounds
	var instant := pistol.duplicate() as WeaponData
	instant.camera_view_size = 20.0
	instant.camera_transition_seconds = 0.0
	slots.secondary_weapon = instant
	_key(KEY_2)
	_check("zero duration applies the equipped view immediately", is_equal_approx(camera.size, 20.0))
	_check("camera configuration preserves weapon ranges and ammo configuration", pistol.fire_range == fire_range and pistol.aim_range == aim_range and combat.ammo.magazine_rounds == magazine)
	var fallback := WeaponData.new()
	fallback.camera_follows_aim_range = false
	combat.equip_weapon(fallback)
	await _frames(22)
	_check("an unconfigured resource restores the scene default", is_equal_approx(camera.size, base_size))
	combat.equip_weapon(instant)
	combat.equip_weapon(null)
	await _frames(22)
	_check("unequipping also restores the scene default", is_equal_approx(camera.size, base_size))
	var invalid := WeaponData.new()
	invalid.camera_follows_aim_range = false
	invalid.camera_view_size = NAN
	invalid.camera_transition_seconds = NAN
	combat.equip_weapon(invalid)
	await _frames(22)
	_check("non-finite resource values cannot poison the lens", is_equal_approx(camera.size, base_size))
	var save_error := ResourceSaver.save(rifle, "user://camera-weapon-roundtrip.tres")
	var restored: WeaponData = ResourceLoader.load("user://camera-weapon-roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("view size and duration survive resource save and reload", save_error == OK and restored.camera_view_size == 17.0 and restored.camera_transition_seconds == 0.3)
	DirAccess.remove_absolute("user://camera-weapon-roundtrip.tres")
	# 原锚点仍消费身体公开的地面高度，相机扩展不跟随翻越的额外抬升。
	actor.global_position += Vector3(2, 0, 1)
	await _frames(3)
	_check("the original anchor follows player ground position", camera.get_node("CameraGroundAnchor").global_position.is_equal_approx(Vector3(actor.global_position.x, actor.get_camera_ground_height(), actor.global_position.z)))
	await _check_movement_interpolation(actor, camera)
	await _check_reticle_interpolation(actor, camera)
	actor.get_node("Health").debug_mode = false
	actor.receive_hit(10000.0)
	_check("existing death still pauses the world", paused)
	actor.get_node("Health/DeathScreen/Center/Panel/Content/Restart").pressed.emit()
	for frame in 12: await process_frame
	var restarted = current_scene
	var restored_weapon = restarted.get_node("Player/Combat").weapon
	var restarted_camera = restarted.get_node("Camera3D")
	var expected_size: float = restarted_camera._size_for_lock_range(restored_weapon.aim_range) if restored_weapon.camera_follows_aim_range else restored_weapon.camera_view_size
	_check("death restart restores the configured initial weapon view", not paused and is_equal_approx(restarted_camera.size, expected_size))
	restarted.queue_free()
	await process_frame
	print("Player camera: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)


func _check_movement_interpolation(actor: Node3D, camera: Camera3D) -> void:
	# Exercise real input and the existing anchor/Phantom Camera chain between 60 Hz ticks.
	var previous_limit := Engine.max_fps
	Engine.max_fps = 240
	actor.reset_physics_interpolation()
	actor.set_physics_process(true)
	Input.action_press("move_right")
	await _frames(30)
	var previous_tick := Engine.get_physics_frames()
	var previous_actor := actor.get_global_transform_interpolated().origin
	var previous_camera := camera.get_global_transform_interpolated().origin
	var body_between_ticks := false
	var camera_between_ticks := false
	for frame in 120:
		await process_frame
		var tick := Engine.get_physics_frames()
		var body_position := actor.get_global_transform_interpolated().origin
		var camera_position := camera.get_global_transform_interpolated().origin
		if tick == previous_tick:
			body_between_ticks = body_between_ticks or body_position.distance_squared_to(previous_actor) > 0.00000001
			camera_between_ticks = camera_between_ticks or camera_position.distance_squared_to(previous_camera) > 0.00000001
		previous_tick = tick
		previous_actor = body_position
		previous_camera = camera_position
	Input.action_release("move_right")
	actor.set_physics_process(false)
	Engine.max_fps = previous_limit
	_check("moving player renders intermediate positions between physics ticks", body_between_ticks)
	_check("ground-following camera renders intermediate positions between physics ticks", camera_between_ticks)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check_reticle_interpolation(actor: Node3D, camera: Camera3D) -> void:
	var combat = actor.get_node("Combat")
	var reticle = combat.get_node("HUD/Reticle")
	combat.set_physics_process(false)
	var target := ReticleTarget.new()
	actor.get_parent().add_child(target)
	target.origin = actor.global_position
	target.global_position = actor.global_position
	target.reset_physics_interpolation()
	var aim_offset := Vector3(0.2, 1.2, 0.1)
	var previous_limit := Engine.max_fps
	Engine.max_fps = 240
	combat.is_aiming = true
	combat.locked_target = target
	var maximum_error := 0.0
	var physical_separation := 0.0
	var aim_unchanged := true
	for frame in 120:
		await process_frame
		combat._locked_aim_point = target.global_transform * aim_offset
		var physical_aim: Vector3 = combat.get_locked_aim_point()
		reticle._process(0.0)
		var displayed: Vector2 = camera.unproject_position(target.get_global_transform_interpolated() * aim_offset)
		maximum_error = maxf(maximum_error, reticle.position.distance_to(displayed))
		physical_separation = maxf(physical_separation, displayed.distance_to(camera.unproject_position(physical_aim)))
		aim_unchanged = aim_unchanged and combat.get_locked_aim_point() == physical_aim
	_check("moving and rotating lock target has distinct rendered and physical positions", physical_separation > 0.1)
	_check("lock reticle stays on the displayed target between physics ticks", maximum_error < 0.01)
	_check("rendering the reticle preserves the actual ballistic aim point", aim_unchanged)
	combat.clear_target_lock()
	reticle._process(0.0)
	_check("clearing the lock still hides its reticle", not reticle.visible)
	combat.is_aiming = false
	target.queue_free()
	Engine.max_fps = previous_limit


func _frames(count: int) -> void:
	for frame in count: await physics_frame
	await process_frame


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + label)
