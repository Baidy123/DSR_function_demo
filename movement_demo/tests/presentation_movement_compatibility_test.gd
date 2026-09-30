extends SceneTree

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var baseline: Array = await trace(false)
	var with_interfaces: Array = await trace(true)
	for index in baseline.size():
		var a: Dictionary = baseline[index]
		var b: Dictionary = with_interfaces[index]
		if not a.position.is_equal_approx(b.position) or not a.velocity.is_equal_approx(b.velocity) or not is_equal_approx(a.stamina, b.stamina) or not is_equal_approx(a.rotation, b.rotation):
			failures += 1
			print("FAIL movement trace at frame ", index)
	print("Movement compatibility: %d frames, %d differences" % [baseline.size(), failures])
	quit(1 if failures else 0)


func trace(interfaces: bool) -> Array:
	var scene = load("res://scenes/main.tscn").instantiate()
	var player = scene.get_node("Player")
	if not interfaces:
		for path in ["Visual/Presentation", "PlayerPresentation", "ImpactReceiver"]:
			var node = player.get_node(path)
			node.get_parent().remove_child(node)
			node.free()
	root.add_child(scene)
	current_scene = scene
	player.set_physics_process(false)
	scene.get_node("Arena/Enemy/AI").set_physics_process(false)
	player.position = Vector3(0, 0, 2)
	for i in 3: await physics_frame
	var result: Array = []
	for frame in 100:
		for action in ["move_up", "move_right", "sprint"]: Input.action_release(action)
		if frame < 35: Input.action_press("move_up")
		if frame >= 15 and frame < 35: Input.action_press("sprint")
		if frame >= 50 and frame < 80: Input.action_press("move_right")
		player._physics_process(1.0 / 60.0)
		await physics_frame
		result.append({"position": player.position, "velocity": player.velocity, "stamina": player.stamina, "rotation": player.rotation.y})
	for action in ["move_up", "move_right", "sprint"]: Input.action_release(action)
	scene.queue_free()
	for i in 3: await physics_frame
	return result
