extends RefCounted

# 只读试玩记录：不改敌人状态、移动或地图；在 Main metadata 留下最近12秒与停滞快照。
func watch(scene: Node) -> void:
	var enemy = scene.get_node("Arena/Enemy")
	var cover = enemy.get_node("Cover")
	var arena = scene.get_node("Arena")
	var trace: Array = []
	var anchor: Vector3 = enemy.global_position
	var still_seconds := 0.0
	var ticks := 0
	while is_instance_valid(scene):
		await scene.get_tree().physics_frame
		ticks += 1
		if ticks % 6 != 0:
			continue
		var contacts: Array = []
		for index in range(enemy.get_slide_collision_count()):
			var hit = enemy.get_slide_collision(index)
			var body = hit.get_collider()
			contacts.append({"body": str(body.get_path()) if is_instance_valid(body) else "", "normal": hit.get_normal()})
		var sample := {
			"time": Time.get_ticks_msec(), "position": arena.to_local(enemy.global_position),
			"phase": cover.state_label(), "health": enemy.health,
			"hide": arena.to_local(cover.hide_position), "peek": arena.to_local(cover.peek_position),
			"agent_target": arena.to_local(enemy.agent.target_position),
			"path_index": enemy.agent.get_current_navigation_path_index(),
			"timer": cover.timer, "retries": cover.cover_detour_retries,
			"detour": cover.cover_detour_active, "contacts": contacts
		}
		trace.append(sample)
		if trace.size() > 120:
			trace.pop_front()
		scene.set_meta("cover_live_trace", trace)
		if cover.phase != cover.Phase.RUN_TO_COVER or enemy.global_position.distance_to(anchor) > 0.1:
			still_seconds = 0.0
			anchor = enemy.global_position
		else:
			still_seconds += 0.1
			if still_seconds >= 1.2 and not scene.has_meta("cover_stall_capture"):
				scene.set_meta("cover_stall_capture", trace.duplicate(true))
				print("[Cover诊断] 已记录跑向掩体时的停滞；请保留游戏运行。")

# 固定 CoverB 东北侧的有效 Hide，从多条路径实际移动，记录失败位置和寻路拐点。
func run(scene: Node, path_distance: float = -1.0, focused: bool = false, damage_interval: int = 0) -> Dictionary:
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var player = scene.get_node("Player")
	var cover = enemy.get_node("Cover")
	var wall = arena.get_node("NavigationRegion3D/Environment/CoverB")
	enemy.get_node("AI").set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = arena.to_global(Vector3(3, 0, -3))
	cover.debug_cover_selection = false
	if path_distance > 0.0:
		enemy.agent.path_desired_distance = path_distance
	for frame in range(5):
		await scene.get_tree().physics_frame
	cover.look_position = player.global_position
	cover.threat_origin = player.global_position + Vector3.UP * 0.8
	var target := Vector3.INF
	var peek := Vector3.INF
	for candidate in wall.get_candidates(cover.threat_origin, enemy.global_position):
		var point: Vector3 = candidate.hide
		if arena.to_local(point).x < 8.25 or not enemy.get_node("AI")._ranged_point_is_free(point):
			continue
		var next_peek: Vector3 = cover._choose_peek(point, candidate.peeks)
		if next_peek.is_finite() and point.z < target.z:
			target = point
			peek = next_peek
	var results := {}
	if not target.is_finite():
		results["available"] = false
		scene.set_meta("cover_b_corner_results", results)
		return results
	var starts: Array[Vector3] = []
	for x in [8.0, 8.25, 8.5, 9.0, 10.0, 12.0]:
		for z in [-0.5, 0.0, 1.0, 3.0]:
			starts.append(Vector3(x, 0, z))
	for retreat in [false]:
		for index in range(starts.size()):
			if focused and (not retreat or index not in [0, 4]):
				continue
			cover.reset()
			enemy.global_position = arena.to_global(starts[index])
			enemy.velocity = Vector3.ZERO
			cover.look_position = player.global_position
			cover.threat_origin = player.global_position + Vector3.UP * 0.8
			cover.active_cover_body = wall
			cover.hide_position = target
			cover.peek_position = peek
			for frame in range(3):
				await scene.get_tree().physics_frame
			cover.covering_retreat_chance = 1.0 if retreat else 0.0
			cover._start_move(cover.Phase.RUN_TO_COVER, target)
			var arrived := false
			var trace := []
			for frame in range(1000):
				await scene.get_tree().physics_frame
				if damage_interval > 0 and frame == damage_interval:
					var attacker: Vector3 = arena.to_global(Vector3(10, 0, 3))
					enemy.receive_hit(1.0, attacker)
					cover.notice_shot(attacker + Vector3.UP * 0.8, enemy.global_position + Vector3.UP * 0.8)
				var direction: Vector3 = cover.step(1.0 / 60.0, false)
				enemy.move_character(direction, 1.0 / 60.0, cover.movement_multiplier())
				if frame % 60 == 0:
					trace.append({"position": arena.to_local(enemy.global_position), "next": arena.to_local(enemy.agent.get_next_path_position()), "retries": cover.cover_detour_retries, "stuck": cover.cover_stuck_timer, "detour": cover.cover_detour_active, "hide": arena.to_local(cover.hide_position), "timer": cover.timer})
				if cover.phase == cover.Phase.HIDE:
					arrived = true
					break
				if not cover.is_active():
					break
			var key := str(index) + "_" + str(retreat)
			results[key] = {"arrived": arrived, "start": starts[index], "end":arena.to_local(enemy.global_position), "phase":cover.phase, "retries":cover.cover_detour_retries}
			if not arrived or cover.cover_detour_retries > 0:
				results[key]["trace"] = trace
			scene.set_meta("cover_b_corner_progress", results.duplicate(true))
	scene.set_meta("cover_b_corner_results", results)
	return results
