extends SceneTree

var failures: int = 0
var checks: int = 0
var player: CharacterBody3D
var visual: Node3D
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--walls" in OS.get_cmdline_user_args():
		await _run_walls()
		return
	_check(InputMap.has_action("sprint"), "sprint input is configured")
	if not InputMap.has_action("sprint"):
		InputMap.add_action("sprint")
	else:
		var has_shift: bool = false
		for event in InputMap.action_get_events("sprint"):
			if event is InputEventKey and (event.keycode == KEY_SHIFT or event.physical_keycode == KEY_SHIFT):
				has_shift = true
		_check(has_shift, "Shift is bound to sprint")

	await _reset()
	Input.action_press("move_up")
	await _tick(1)
	_check(is_equal_approx(_speed(), 3.0), "walking speed is unchanged")
	Input.action_press("sprint")
	await _tick(1)
	_check(is_equal_approx(_speed(), 6.0), "holding Shift doubles movement speed")
	var straight_distance: float = Vector2(player.position.x, player.position.z).length()
	Input.action_press("move_right")
	visual.rotation.y = -PI / 4.0
	await _tick(1)
	_check(is_equal_approx(_speed(), 6.0), "diagonal sprint has the same speed")
	_check(absf(Vector2(player.position.x, player.position.z).length() - straight_distance) < 0.001, "actual diagonal distance equals straight distance")
	Input.action_release("sprint")
	await _tick(1)
	_check(is_equal_approx(_speed(), 3.0), "releasing Shift returns to walking immediately")

	# 始终按住 Shift，验证整段消耗、锁定和自动恢复。
	await _reset()
	Input.action_press("move_up")
	Input.action_press("sprint")
	await _tick(299)
	_check(is_equal_approx(_speed(), 6.0), "can sprint just before five seconds")
	await _tick(2)
	_check(is_equal_approx(_speed(), 3.0), "exhaustion forces walking after five seconds")
	await _tick(90)
	_check(is_equal_approx(_speed(), 3.0), "partial recovery does not unlock exhausted sprint")
	Input.action_release("sprint")
	await _tick(1)
	Input.action_press("sprint")
	await _tick(1)
	_check(is_equal_approx(_speed(), 3.0), "repressing Shift cannot bypass exhaustion")
	await _tick(86)
	_check(is_equal_approx(_speed(), 3.0), "sprint stays locked until full three-second recovery")
	await _tick(3)
	_check(is_equal_approx(_speed(), 6.0), "holding Shift resumes sprint after full recovery")

	# 未耗尽就松键，恢复的耐力可直接再次使用。
	await _reset()
	Input.action_press("move_up")
	Input.action_press("sprint")
	await _tick(240)
	Input.action_release("sprint")
	await _tick(60)
	Input.action_press("sprint")
	await _tick(120)
	_check(is_equal_approx(_speed(), 6.0), "walking restores stamina before exhaustion")

	# 只按 Shift 不算奔跑；原地转身也不消耗耐力。
	await _reset()
	Input.action_press("sprint")
	await _tick(330)
	_check(is_zero_approx(_speed()), "Shift alone does not move the player")
	Input.action_press("move_up")
	await _tick(240)
	_check(is_equal_approx(_speed(), 6.0), "standing with Shift held preserves stamina")
	for frame in range(90):
		visual.rotation.y = PI / 2.0
		await _tick(1)
	_check(is_zero_approx(_speed()), "sprinting still stops translation while turning")
	visual.rotation.y = 0.0
	await _tick(120)
	_check(is_equal_approx(_speed(), 6.0), "turning restores stamina")

	_release_inputs()
	print("Sprint checks: ", failures, " failure(s)")
	quit(1 if failures else 0)


func _reset() -> void:
	_release_inputs()
	if is_instance_valid(scene):
		scene.free()
	scene = preload("res://tests/enemy/enemy_fire_fixture.gd").unbound_scene()
	root.add_child(scene)
	player = scene.get_node("Player")
	visual = player.get("visual")
	player.set_physics_process(false)
	await _tick(3)


func _tick(count: int) -> void:
	for frame in range(count):
		await physics_frame
		# 回到场地中央，避免长时间奔跑测试撞墙；每帧仍执行真实移动。
		player.position = Vector3.ZERO
		player._physics_process(1.0 / Engine.physics_ticks_per_second)


func _speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _release_inputs() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "sprint"]:
		Input.action_release(action)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run_walls() -> void:
	# Keep the real player subtree, but use a controlled room and continuous
	# physical movement instead of the legacy test's per-frame teleport.
	var donor = preload("res://tests/enemy/enemy_fire_fixture.gd").unbound_scene()
	player = donor.get_node("Player")
	donor.remove_child(player)
	donor.free()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	_wall_box(Vector3(30, 0.2, 30), Vector3(0, -0.1, 0))
	_wall_box(Vector3(30, 3, 0.4), Vector3(0, 1.5, -2.5))
	player.position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	scene.add_child(player)
	player.set_physics_process(false)
	player.move_speed = 3.0
	player.acceleration_time = 0.3
	player.deceleration_time = 0.2
	player.stamina_recovery_delay = 0.5
	_release_inputs()
	await _wall_tick(5)
	Input.action_press("move_up")
	Input.action_press("sprint")
	await _wall_tick(25)
	_check(player.is_sprinting and player.current_speed > 3.0 and player.stamina < 100.0, "unobstructed acceleration still sprints and consumes stamina")
	await _wall_tick(35)
	_check(player.is_on_wall() and absf(player.get_real_velocity().z) < 0.01, "real collision stops the player against the wall")
	_check(not player.is_sprinting and player.current_speed < 0.01, "holding sprint against the wall clears sprint and stored speed")
	var stamina_at_wall: float = player.stamina
	await _wall_tick(10)
	_check(player.stamina >= stamina_at_wall, "continued wall pressure does not spend stamina")
	await _wall_tick(60)
	_check(player.stamina > stamina_at_wall, "stamina recovers after the normal delay while blocked")
	Input.action_release("move_up")
	Input.action_press("move_right")
	var departure: Vector3 = player.global_position
	await _wall_tick(9)
	_check(player.is_sprinting and player.position.x > departure.x and player.current_speed < 2.0, "turning away resumes sprint through normal acceleration")
	# A diagonal wall slide has actual movement and should remain a sprint.
	player.position = Vector3(0, 0, -1.94)
	player.rotation.y = -PI / 4.0
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	Input.action_press("move_up")
	var before_slide: float = player.stamina
	await _wall_tick(40)
	_check(player.is_sprinting and player.position.x > 1.0 and absf(player.get_real_velocity().z) < 0.01, "diagonal wall sliding keeps sprint when it actually moves")
	_check(player.stamina < before_slide, "actual wall sliding retains sprint stamina cost")
	_wall_box(Vector3(0.4, 3, 10), Vector3(3, 1.5, -2))
	await _wall_tick(80)
	_check(not player.is_sprinting and player.current_speed < 0.01 and player.get_real_velocity().length() < 0.02, "two-wall corner also clears blocked sprint")
	# A sideways external impulse must not count as successful forward sprint.
	_release_inputs()
	player.position = Vector3(0, 0, -1.949)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	await _wall_tick(3)
	Input.action_press("move_up")
	Input.action_press("sprint")
	player.receive_melee_hit(0.0, player.global_position - Vector3.RIGHT, 0.8, 0.25)
	var before_push: float = player.stamina
	await _wall_tick(2)
	_check(player.position.x > 0.05 and not player.is_sprinting and player.stamina >= before_push, "external sideways push is preserved without counting as sprint through a wall")
	_release_inputs()
	print("Sprint wall checks: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _wall_tick(count: int) -> void:
	for frame in count:
		await physics_frame
		player._physics_process(1.0 / 60.0)


func _wall_box(size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	scene.add_child(body)
	body.position = position
