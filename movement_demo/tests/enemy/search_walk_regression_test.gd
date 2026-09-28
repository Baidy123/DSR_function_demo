extends SceneTree

# 复用既有真实绕墙与搜索覆盖检查，仅运行本步涉及的部分。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Arena/Enemy").shooting_enabled = false
	for frame in range(5): await physics_frame
	seed(20260920)
	var checks: Dictionary = await load("res://tests/enemy/cover_search_regression_test.gd").new().run(scene)
	var failed := 0
	for label in checks:
		if not checks[label]: failed += 1
		print("PASS " if checks[label] else "FAIL ", label)
	print("SEARCH WALK: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 and checks.size() == 29 else 1)
