extends SceneTree

# 同一组行为检查在拆分前后运行；每组使用新的 Main，避免运行状态相互污染。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var suites := [
		["res://tests/cover_search_regression_test.gd", "run"],
		["res://tests/cover_damage_reaction_test.gd", "run"],
		["res://tests/arena_activation_test.gd", "run"],
		["res://tests/cover_four_faces_test.gd", "run"],
		["res://tests/cover_four_faces_test.gd", "run_short_walk"],
		["res://tests/cover_region_test.gd", "run"],
		["res://tests/cover_region_test.gd", "run_walk"],
		["res://tests/cover_region_test.gd", "run_cycle"],
	]
	var total: int = 0
	var failures: int = 0
	for suite in suites:
		if current_scene != null:
			current_scene.free()
		var scene = load("res://main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		for frame in range(5):
			await physics_frame
		seed(20260920)
		var checks: Dictionary = await load(suite[0]).new().call(suite[1], scene)
		var failed: Array = []
		for label in checks:
			if not checks[label]:
				failed.append(label)
		total += checks.size()
		failures += failed.size()
		print("AI REGRESSION ", suite[0], "/", suite[1], ": ", checks.size() - failed.size(), "/", checks.size(), " failed=", failed)
	print("AI REGRESSION TOTAL: ", total - failures, "/", total)
	quit(0 if failures == 0 else 1)
