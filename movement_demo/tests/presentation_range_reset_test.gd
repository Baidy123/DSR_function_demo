extends SceneTree

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var result: Dictionary = await load("res://tests/range_reset_test.gd").new().run(scene)
	var failures := 0
	for key in result:
		print(("PASS " if result[key] else "FAIL ") + key)
		if not result[key]: failures += 1
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
