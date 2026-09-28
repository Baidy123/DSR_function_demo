extends SceneTree

var failures: int = 0
var player: CharacterBody3D
var visual: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	player = scene.get_node("Player")
	visual = player.get("visual")
	player.set_physics_process(false)
	await _tick(3)

	# 初始朝上，按右后必须转动，但还不能移动。
	Input.action_press("move_right")
	var start: Vector3 = player.position
	await _tick(1)
	_check(_flat_distance(start, player.position) < 0.001, "no translation while turning")
	_check(absf(visual.rotation.y) > 0.001, "turn begins gradually")
	_check(absf(visual.rotation.y) < PI / 2.0 - 0.01, "no instant 90-degree turn")

	await _tick(50)
	_check(player.position.x > start.x + 0.2, "moves right after turn")
	_check((-visual.global_basis.z).dot(Vector3.RIGHT) > 0.999, "faces right")
	Input.action_release("move_right")

	# 从正在右移的状态改为左移，第一帧就停止位移。
	Input.action_press("move_left")
	start = player.position
	await _tick(1)
	_check(_flat_distance(start, player.position) < 0.001, "direction change stops translation")
	Input.action_release("move_left")
	var stopped_angle: float = visual.rotation.y
	await _tick(5)
	_check(_flat_distance(start, player.position) < 0.001, "release stops movement")
	_check(is_equal_approx(visual.rotation.y, stopped_angle), "release stops turning")

	# 直接设定测试起点与朝向，比较直行和斜行实际距离。
	player.position = Vector3.ZERO
	visual.rotation.y = 0.0
	Input.action_press("move_up")
	await _tick(15)
	var straight_distance: float = _flat_distance(Vector3.ZERO, player.position)
	Input.action_release("move_up")
	player.position = Vector3.ZERO
	visual.rotation.y = -PI / 4.0
	Input.action_press("move_up")
	Input.action_press("move_right")
	await _tick(15)
	var diagonal_distance: float = _flat_distance(Vector3.ZERO, player.position)
	_check(straight_distance > 0.2, "forward movement exists")
	_check(absf(straight_distance - diagonal_distance) < 0.01, "diagonal speed equals straight speed")
	_check(player.position.x > 0.1 and player.position.z < -0.1, "W+D moves upper-right")
	Input.action_release("move_up")
	Input.action_release("move_right")

	Input.action_press("move_left")
	Input.action_press("move_right")
	start = player.position
	await _tick(5)
	_check(_flat_distance(start, player.position) < 0.001, "opposite keys cancel")
	Input.action_release("move_left")
	Input.action_release("move_right")

	# 真实场景内撞到边界，应留在场地内且不掉落。
	player.position = Vector3(8.4, 0, 0)
	visual.rotation.y = -PI / 2.0
	Input.action_press("move_right")
	await _tick(60)
	_check(player.position.x < 8.7, "border collision blocks player")
	_check(absf(player.position.y) < 0.05, "player remains on floor")
	Input.action_release("move_right")

	print("Movement checks: ", failures, " failure(s)")
	quit(1 if failures else 0)


func _tick(count: int) -> void:
	for frame in range(count):
		await physics_frame
		if player.has_method("_physics_process"):
			player._physics_process(1.0 / Engine.physics_ticks_per_second)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)
	else:
		print("PASS: ", label)
