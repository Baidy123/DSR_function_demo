extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	enemy.get_node("AI").set_physics_process(false)
	enemy.get_node("AI").cover_selection.debug_attack_points = false
	enemy.get_node("AI").actions[&"search"].debug_tracking_cheat = false
	enemy.shooting_enabled = false
	scene.get_node("Player").set_physics_process(false)
	for frame in range(8): await physics_frame
	var checks: Dictionary = await _check_search(scene, enemy)
	for label in checks: print("PASS " if checks[label] else "FAIL ", label)
	print("SEARCH AREA: %d/%d passed" % [checks.values().count(true), checks.size()])
	quit(0 if checks.size() == 22 and checks.values().all(func(v): return v) else 1)

func _check_search(scene: Node, enemy: Node) -> Dictionary:
	var ai = enemy.get_node("AI")
	var checks := {}
	var arena = enemy.get_parent()
	var player = scene.get_node("Player")
	var tree = scene.get_tree()
	ai.reset_actions()
	enemy.global_position = arena.to_global(Vector3(0, 0, 0))
	player.global_position = arena.to_global(Vector3(2, 0, 0))
	for frame in range(4):
		await tree.physics_frame
	enemy.look_at(player.global_position)
	ai._physics_process(0.0)
	var seen: Vector3 = ai.last_seen_position
	ai.context._investigate_attack(player.global_position + Vector3(0, 0, 2))
	ai.actions[&"search"].begin_search()
	checks["search_center_uses_true_sighting"] = ai.actions[&"search"].search_origin.is_equal_approx(seen)
	ai.actions[&"search"]._advance_systematic_search_target()
	var before: float = ai.actions[&"search"].get_search_coverage()
	ai.actions[&"search"]._skip_current_search_point()
	checks["failed_goal_does_not_count_as_coverage"] = is_equal_approx(before, ai.actions[&"search"].get_search_coverage())

	player.global_position = Vector3.ZERO
	for frame in range(4):
		await tree.physics_frame
	ai.set_physics_process(false)
	ai.actions[&"search"].search_seconds = 0.0
	ai.actions[&"search"].search_hint_chance = 0.0
	var old_scale: float = Engine.time_scale
	Engine.time_scale = 8.0
	for random_seed in [101, 202, 303]:
		seed(random_seed)
		enemy.reset_target()
		enemy.global_position = arena.to_global(Vector3(0, 0, 0))
		ai.last_known_position = enemy.global_position
		ai.actions[&"search"].begin_search()
		var origin: Vector3 = ai.actions[&"search"].search_origin
		var visited: Array[Vector3] = []
		var maximum_coverage: float = 0.0
		var inside := true
		var free := true
		var path_does_not_count := true
		for frame in range(1600):
			await tree.physics_frame
			var active: bool = ai.actions[&"search"].search_current_target_active
			var target: Vector3 = ai.actions[&"search"].search_current_target
			before = ai.actions[&"search"].get_search_coverage()
			var delta: float = enemy.get_physics_process_delta_time()
			var direction: Vector3 = ai.actions[&"search"]._process_search(delta)
			enemy.move_character(direction, delta, ai.actions[&"search"].search_move_speed_multiplier)
			if ai.state != ai.State.SEARCH:
				break
			if active and not ai.actions[&"search"].search_current_target_active and ai.actions[&"search"].get_search_coverage() > before:
				visited.append(target)
			if ai.actions[&"search"].search_current_target_active:
				inside = inside and ai.context._horizontal_distance_between(ai.actions[&"search"].search_current_target, origin) <= ai.actions[&"search"].search_radius + 0.001
				free = free and ai.context.is_position_free(ai.actions[&"search"].search_current_target)
				path_does_not_count = path_does_not_count and is_equal_approx(before, ai.actions[&"search"].get_search_coverage())
			maximum_coverage = maxf(maximum_coverage, ai.actions[&"search"].get_search_coverage())
		var suffix := "_" + str(random_seed)
		checks["walk_finishes_coverage" + suffix] = maximum_coverage >= ai.actions[&"search"].search_coverage_goal
		checks["returns_to_idle" + suffix] = ai.state == ai.State.IDLE and not ai.is_alerted
		checks["targets_inside_circle" + suffix] = inside
		checks["targets_have_body_space" + suffix] = free
		checks["path_waypoints_do_not_count" + suffix] = path_does_not_count
		# 独立的更密地面采样，避免只用选点算法自己的网格证明覆盖。
		var valid_samples := 0
		var covered_samples := 0
		for x in range(-14, 15):
			for z in range(-14, 15):
				var point := origin + Vector3(x * 0.35, 0, z * 0.35)
				if ai.context._horizontal_distance_between(point, origin) > ai.actions[&"search"].search_radius:
					continue
				var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), point)
				if ai.context._horizontal_distance_between(point, nav_point) > 0.1 or not ai.context.is_position_free(point):
					continue
				valid_samples += 1
				for goal in visited:
					if ai.context._horizontal_distance_between(goal, point) <= ai.actions[&"search"].search_coverage_radius:
						covered_samples += 1
						break
		var dense_coverage: float = float(covered_samples) / maxf(1.0, valid_samples)
		checks["independent_area_coverage_over_90_percent" + suffix] = dense_coverage >= 0.9
		print("[CoverageTest] seed=", random_seed, " goals=", visited.size(), " planner=", maximum_coverage, " dense=", dense_coverage)
	Engine.time_scale = old_scale

	ai.actions[&"search"].begin_search()
	enemy.receive_hit(100000.0)
	checks["death_clears_search"] = ai.actions[&"search"].coverage.uncovered.is_empty() and not ai.actions[&"search"].search_current_target_active
	enemy.reset_target()
	checks["reset_clears_search_and_visual_memory"] = ai.actions[&"search"].coverage.uncovered.is_empty() and not ai.has_visual_memory
	return checks
