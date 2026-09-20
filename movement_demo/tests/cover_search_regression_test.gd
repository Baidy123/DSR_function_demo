extends RefCounted

# 在 Main 的独立测试运行中调用 run；不会保存运行时节点位置或参数。
func run(scene: Node) -> Dictionary:
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var cover = enemy.get_node("Cover")
	var arena = enemy.get_parent()
	var tree = scene.get_tree()
	scene.get_node("Player").set_physics_process(false)
	ai.set_physics_process(false)
	cover.debug_cover_selection = false
	var checks := {}
	for retreat: bool in [false, true]:
		enemy.global_position = arena.to_global(Vector3(-4.75126, 0, 3.100522))
		enemy.velocity = Vector3.ZERO
		cover.reset()
		cover.threat_origin = arena.to_global(Vector3(7, 0.8, 2))
		cover.look_position = cover.threat_origin - Vector3.UP * 0.8
		var chosen: bool = cover._choose_cover()
		checks["repro_selects_cover_" + str(retreat)] = chosen
		cover._start_move(cover.Phase.RUN_TO_COVER, cover.hide_position)
		cover.covering_retreat = retreat
		var started := false
		var hidden := false
		for frame in range(240):
			await tree.physics_frame
			var direction: Vector3 = cover.step(1.0 / 60.0, false)
			started = started or not direction.is_zero_approx()
			enemy.move_character(direction, 1.0 / 60.0, cover.movement_multiplier())
			if cover.phase == cover.Phase.HIDE:
				hidden = cover._selected_cover_blocks(enemy.global_position, cover.threat_origin)
				break
			if not cover.is_active():
				break
		checks["moves_past_exposed_arrival_" + str(retreat)] = started
		checks["reaches_real_cover_" + str(retreat)] = hidden

	cover.reset()
	enemy.global_position = arena.to_global(Vector3(0, 0, 0))
	ai.last_known_position = enemy.global_position
	ai.search_seconds = 0.0
	ai.search_hint_chance = 0.0
	var first_targets: Array[Vector3] = []
	for random_seed in [101, 202, 303, 404]:
		seed(random_seed)
		ai.search_direction = Vector3.FORWARD
		ai.last_seen_direction = Vector3.ZERO
		ai._begin_search()
		ai._advance_systematic_search_target()
		first_targets.append(ai.search_current_target)
	var varied := false
	for point in first_targets:
		varied = varied or not point.is_equal_approx(first_targets[0])
	checks["search_targets_vary_between_runs"] = varied
	checks.merge(await _check_search(scene, enemy))
	scene.set_meta("cover_search_checks", checks)
	return checks


func _check_search(scene: Node, enemy: Node) -> Dictionary:
	var ai = enemy.get_node("AI")
	var checks := {}
	var arena = enemy.get_parent()
	var player = scene.get_node("Player")
	var tree = scene.get_tree()
	enemy.get_node("Cover").reset()
	enemy.global_position = arena.to_global(Vector3(0, 0, 0))
	player.global_position = arena.to_global(Vector3(2, 0, 0))
	for frame in range(4):
		await tree.physics_frame
	enemy.look_at(player.global_position)
	ai._physics_process(0.0)
	var seen: Vector3 = ai.last_seen_position
	ai._investigate_attack(player.global_position + Vector3(0, 0, 2))
	ai._begin_search()
	checks["search_center_uses_true_sighting"] = ai.search_origin.is_equal_approx(seen)
	ai._advance_systematic_search_target()
	var before: float = ai.get_search_coverage()
	ai._skip_current_search_point()
	checks["failed_goal_does_not_count_as_coverage"] = is_equal_approx(before, ai.get_search_coverage())

	player.global_position = Vector3.ZERO
	for frame in range(4):
		await tree.physics_frame
	ai.set_physics_process(false)
	ai.search_seconds = 0.0
	ai.search_hint_chance = 0.0
	var old_scale: float = Engine.time_scale
	Engine.time_scale = 8.0
	for random_seed in [101, 202, 303]:
		seed(random_seed)
		enemy.reset_target()
		enemy.global_position = arena.to_global(Vector3(0, 0, 0))
		ai.last_known_position = enemy.global_position
		ai._begin_search()
		var origin: Vector3 = ai.search_origin
		var visited: Array[Vector3] = []
		var maximum_coverage: float = 0.0
		var inside := true
		var free := true
		var path_does_not_count := true
		for frame in range(1600):
			await tree.physics_frame
			var active: bool = ai.search_current_target_active
			var target: Vector3 = ai.search_current_target
			before = ai.get_search_coverage()
			var delta: float = enemy.get_physics_process_delta_time()
			var direction: Vector3 = ai._process_search(delta)
			enemy.move_character(direction, delta, ai.search_move_speed_multiplier)
			if ai.state != ai.State.SEARCH:
				break
			if active and not ai.search_current_target_active and ai.get_search_coverage() > before:
				visited.append(target)
			if ai.search_current_target_active:
				inside = inside and ai._horizontal_distance_between(ai.search_current_target, origin) <= ai.search_radius + 0.001
				free = free and ai._ranged_point_is_free(ai.search_current_target)
				path_does_not_count = path_does_not_count and is_equal_approx(before, ai.get_search_coverage())
			maximum_coverage = maxf(maximum_coverage, ai.get_search_coverage())
		var suffix := "_" + str(random_seed)
		checks["walk_finishes_coverage" + suffix] = maximum_coverage >= ai.search_coverage_goal
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
				if ai._horizontal_distance_between(point, origin) > ai.search_radius:
					continue
				var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), point)
				if ai._horizontal_distance_between(point, nav_point) > 0.1 or not ai._ranged_point_is_free(point):
					continue
				valid_samples += 1
				for goal in visited:
					if ai._horizontal_distance_between(goal, point) <= ai.search_coverage_radius:
						covered_samples += 1
						break
		var dense_coverage: float = float(covered_samples) / maxf(1.0, valid_samples)
		checks["independent_area_coverage_over_90_percent" + suffix] = dense_coverage >= 0.9
		print("[CoverageTest] seed=", random_seed, " goals=", visited.size(), " planner=", maximum_coverage, " dense=", dense_coverage)
	Engine.time_scale = old_scale

	ai._begin_search()
	enemy.receive_hit(100000.0)
	checks["death_clears_search"] = ai.search_uncovered_points.is_empty() and not ai.search_current_target_active
	enemy.reset_target()
	checks["reset_clears_search_and_visual_memory"] = ai.search_uncovered_points.is_empty() and not ai.has_visual_memory
	return checks
