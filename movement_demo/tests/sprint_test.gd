extends SceneTree

var failures: int = 0
var player: CharacterBody3D
var visual: Node3D
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	scene = load("res://main.tscn").instantiate()
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
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)