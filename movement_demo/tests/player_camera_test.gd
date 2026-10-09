extends SceneTree

var checks := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene = packed.instantiate()
	var actor = scene.get_node("Player")
	var slots = actor.get_node("WeaponSlots")
	var combat = actor.get_node("Combat")
	var camera = scene.get_node("Camera3D")
	var base_size: float = camera.size
	var pistol: WeaponData = slots.primary_weapon.duplicate()
	var rifle: WeaponData = slots.secondary_weapon.duplicate()
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
	_check("existing camera host and ground anchor remain connected", camera.has_node("PhantomCameraHost") and scene.get_node("PhantomCamera3D").follow_target == scene.get_node("CameraGroundAnchor"))
	_check("camera projection stays orthogonal", camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	_check("third-party camera only follows the transform without a competing lens override", scene.get_node("PhantomCamera3D").camera_3d_resource == null)
	var follow_offset: Vector3 = scene.get_node("PhantomCamera3D").follow_offset
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
	_check("weapon view does not change camera tilt or follow offset", scene.get_node("PhantomCamera3D").follow_offset == follow_offset)
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
	combat.equip_weapon(fallback)
	await _frames(22)
	_check("an unconfigured resource restores the scene default", is_equal_approx(camera.size, base_size))
	combat.equip_weapon(instant)
	combat.equip_weapon(null)
	await _frames(22)
	_check("unequipping also restores the scene default", is_equal_approx(camera.size, base_size))
	var invalid := WeaponData.new()
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
	_check("the original anchor follows player ground position", scene.get_node("CameraGroundAnchor").global_position.is_equal_approx(Vector3(actor.global_position.x, actor.get_camera_ground_height(), actor.global_position.z)))
	actor.get_node("Health").debug_mode = false
	actor.receive_hit(10000.0)
	_check("existing death still pauses the world", paused)
	actor.get_node("Health/DeathScreen/Center/Panel/Content/Restart").pressed.emit()
	for frame in 12: await process_frame
	var restarted = current_scene
	var restored_weapon = restarted.get_node("Player/Combat").weapon
	_check("death restart restores the configured initial weapon view", not paused and is_equal_approx(restarted.get_node("Camera3D").size, restored_weapon.camera_view_size))
	restarted.queue_free()
	await process_frame
	print("Player camera: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for frame in count: await physics_frame
	await process_frame


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + label)
