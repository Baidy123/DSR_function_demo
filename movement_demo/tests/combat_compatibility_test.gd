extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var count := 0
	var failed := 0
	for name in ["aim_mode_test", "spread_cone_test", "player_move_spread_test", "weapon_mode_parameters_test", "shot_collision_test"]:
		var scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		var results: Dictionary = await load("res://tests/" + name + ".gd").new().run(scene)
		for label in results:
			count += 1
			if not results[label]:
				failed += 1
				push_error(name + ": " + label)
		print(name, ": ", results.values().filter(func(value): return value).size(), "/", results.size())
		scene.queue_free()
		await process_frame
	print("COMBAT COMPATIBILITY: %d/%d passed" % [count - failed, count])
	quit(1 if failed else 0)
