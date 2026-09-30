extends SceneTree

class MovementDriver extends Node:
	var actor
	var direction := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		actor.move_character(direction, delta)

var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(10, 0, 10)
	var actor = scene.get_node("Arena/Enemy")
	actor.get_node("AI").set_physics_process(false)
	for target in get_nodes_in_group("combat_target"):
		if target != actor: target.global_position = Vector3(30, 0, 30)
	scene.get_node("CombatTest/Cover").global_position = Vector3(30, 0, 30)
	var driver := MovementDriver.new()
	driver.actor = actor
	scene.add_child(driver)
	for rate in [30, 60, 120]:
		Engine.physics_ticks_per_second = rate
		for driven in [false, true]:
			driver.set_physics_process(driven)
			actor.global_position = Vector3(0, 0, -3)
			actor.velocity = Vector3.ZERO
			await _frames(3)
			var before: Vector3 = actor.global_position
			actor.receive_melee_hit(1.0, before + Vector3.BACK, 1.0, 0.2)
			await _frames(int(ceil(rate * 0.2)) + 2)
			var travelled := Vector2(actor.global_position.x - before.x, actor.global_position.z - before.z).length()
			_check("%dHz %s击退约1米且不重复推进" % [rate, "有正常移动调用" if driven else "无AI移动调用"], absf(travelled - 1.0) < 0.045)
	Engine.physics_ticks_per_second = 60
	driver.direction = Vector3.RIGHT
	actor.global_position = Vector3(0, 0, -3)
	await _frames(2)
	var before: Vector3 = actor.global_position
	actor.receive_melee_hit(1.0, before + Vector3.BACK, 1.0, 0.2)
	await _frames(14)
	_check("自主横移与向后击退正确合成", actor.global_position.x > before.x + 0.2 and absf(actor.global_position.z - before.z + 1.0) < 0.045)
	scene.queue_free()
	await process_frame
	await process_frame
	var passed := 0
	for name in checks:
		if checks[name]: passed += 1
	print("Melee physics: %d/%d passed" % [passed, checks.size()])
	quit(0 if passed == checks.size() else 1)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _check(title: String, passed: bool) -> void:
	checks[title] = passed
	print(("PASS " if passed else "FAIL ") + title)
