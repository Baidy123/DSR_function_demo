extends "res://tests/enemy/enemy_ally_navigation_test.gd"

var reports := 0
var max_observation := 0.0
var report_action: StringName = &""

func _run() -> void:
	seed(28)
	await _setup()
	for actor in actors: actor.get_node("AI").set_physics_process(false)
	_make_corridor(false)
	var navigation: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-4, 0.5, -0.45), Vector3(4, 0.5, -0.45), Vector3(4, 0.5, 0.45), Vector3(-4, 0.5, 0.45)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	await _reset(Vector3(-1.2, 0, 0), Vector3.ZERO)
	# The inherited scene spawned before this narrower test region existed.
	# Re-enter through the real lifecycle so spawn validation uses these bodies.
	for actor in actors:
		actor.get_node("AI").context.detach_environment()
		actor.get_node("AI").context.refresh_environment()
	var mover = actors[0]
	var blocker = actors[1]
	var ai = mover.get_node("AI")
	var context = ai.context
	var player = scene.get_node("Player")
	player.global_position = arena.to_global(Vector3(3, 0, 0))
	# Isolate genuine hearing from visual combat. Keep the original search stall
	# timer, action selection, movement speeds and local avoidance unchanged.
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	ai.actions[&"search"].tracking_cheat_enabled = false
	check(blocker.begin_melee(10.0), "真实禁移友军堵住无侧向出口的窄口")
	mover.ally_path_blocked.connect(func(_body, _point):
		reports += 1
		report_action = ai.utility_current.get("id", &""))
	for frame in 6: await physics_frame
	check(ai.is_arena_active() and not ai.perception.can_see_player(), "实际玩家在战斗区，听觉调查夹具没有视觉接敌")
	var noise := NoiseData.new()
	noise.occluded_range_multiplier = 1.0
	noise.emit_from(player, 15.0)
	var saw_search := false
	var saw_blocked_target := false
	var targets: Array[Vector3] = []
	var start: Vector3 = mover.global_position
	var phases: Array = []
	var maximum_stall := 0.0
	for frame in 720:
		await physics_frame
		# Two further real footsteps keep this a repeated investigation of the
		# same choke even when the narrow sampled search area is exhausted.
		if frame == 72 or frame == 144:
			player.global_position = arena.to_global(Vector3(3.5 if frame == 72 else 3.0, 0, 0))
			noise.emit_from(player, 15.0)
		ai._physics_process(STEP)
		blocker.move_character(Vector3.ZERO, STEP)
		saw_search = saw_search or ai.utility_current.get("id") == &"search"
		max_observation = maxf(max_observation, mover.local_motion._blocked_seconds)
		var search = ai.actions[&"search"]
		var phase := Vector2i(context.state, search.investigation_phase)
		if phases.is_empty() or phases[-1].phase != phase: phases.append({"frame": frame, "phase": phase})
		maximum_stall = maxf(maximum_stall, maxf(search._track_stuck_seconds, search.search_stuck_timer))
		if ai.utility_current.get("id") == &"search":
			var target: Vector3 = ai.actions[&"search"].utility_destination()
			if target.x > blocker.global_position.x + 0.5:
				saw_blocked_target = true
				if not targets.has(target): targets.append(target)
		if not context._blocked_ally_paths.is_empty(): break
	check(saw_search and saw_blocked_target, "真实声音经听觉与普通Utility自主选择经过堵口的调查")
	check(reports > 0 and report_action == &"search" and not context._blocked_ally_paths.is_empty(), "完整AI在搜索动作结束前积累并登记实际堵点，不依赖其他动作偶然再次卡住")
	print("AUTONOMOUS BLOCK reports=", reports, " action=", report_action, " observation=", max_observation, " targets=", targets, " start=", start, " position=", mover.global_position, " phases=", phases, " max_stall=", maximum_stall, " limit=", ai.actions[&"search"].search_stuck_repath_seconds)
	if context._blocked_ally_paths.is_empty():
		print("ALLY ROUTE AUTONOMOUS: %d/%d passed" % [checks - failures, checks])
		quit(1)
		return
	var destination: Vector3 = arena.to_global(Vector3(3, 0, 0))
	var second: Vector3 = arena.to_global(Vector3(3.5, 0, 0))
	check(context.cover_selection._path_to(mover.global_position, destination).is_empty() and context.cover_selection._path_to(mover.global_position, second).is_empty(), "自主登记后不同终点共用真实堵口限制")
	var held := true
	for frame in 60:
		await physics_frame
		ai._physics_process(STEP)
		blocker.move_character(Vector3.ZERO, STEP)
		held = held and context.cover_selection._path_to(mover.global_position, destination).is_empty()
	check(held and mover.global_position.x < blocker.global_position.x, "原动作重评期间堵路约束持续有效且身体没有穿透")
	# Keep the same actual obstruction beyond its finite memory lifetime. Real
	# new footsteps may legitimately select this passage again after expiry.
	var first_deadline: float = context._blocked_ally_paths[0].valid_until if not context._blocked_ally_paths.is_empty() else -INF
	var report_times: Array[float] = [mover.local_motion._blocked_reported_at]
	var previous_reports: int = reports
	var expired_seen := false
	var fresh_attempt := false
	var still_separated := true
	for frame in 720:
		await physics_frame
		if frame % 90 == 0:
			player.global_position = arena.to_global(Vector3(3.5 if (frame / 90) % 2 == 0 else 3.0, 0, 0))
			noise.emit_from(player, 15.0)
		ai._physics_process(STEP)
		blocker.move_character(Vector3.ZERO, STEP)
		if context.evidence_elapsed_seconds >= first_deadline and context._blocked_ally_paths.is_empty(): expired_seen = true
		if expired_seen and not mover.local_motion._desired.is_zero_approx(): fresh_attempt = true
		if reports > previous_reports: report_times.append(mover.local_motion._blocked_reported_at)
		previous_reports = reports
		still_separated = still_separated and mover.global_position.x < blocker.global_position.x and mover.global_position.distance_to(blocker.global_position) >= 0.68
	var bounded_reports := true
	for index in range(1, report_times.size()):
		bounded_reports = bounded_reports and report_times[index] - report_times[index - 1] >= 5.2
	check(expired_seen and fresh_attempt and reports >= 2, "Finite route evidence can expire and a new real autonomous failure reports the same blocked passage again")
	check(bounded_reports, "Repeated blockage reports require cooldown and a fresh physical observation window")
	check(still_separated, "Repeated investigation after expiry never crosses the stationary body")
	print("AUTONOMOUS BLOCK EXPIRY reports=", reports, " times=", report_times, " expired=", expired_seen, " fresh_attempt=", fresh_attempt)
	blocker.cancel_melee()
	blocker.global_position = arena.to_global(Vector3(0, 0, 3))
	# A new real sound at a distinct nearby point is a new observation, avoiding
	# the existing deduplication of the original hearing event.
	player.global_position = arena.to_global(Vector3(3.5, 0, 0))
	noise.emit_from(player, 15.0)
	for frame in 720:
		await physics_frame
		ai._physics_process(STEP)
		if mover.global_position.x > arena.global_position.x + 1.0: break
	check(context._blocked_ally_paths.is_empty(), "队友移开后完整AI自动清除堵路记忆")
	check(mover.global_position.x > arena.global_position.x + 1.0, "新真实声音驱动原Utility恢复调查并实际通过原窄口")
	print("ALLY ROUTE AUTONOMOUS: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
