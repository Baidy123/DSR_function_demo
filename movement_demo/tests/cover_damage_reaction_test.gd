extends RefCounted

func run(scene: Node) -> Dictionary:
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var cover = enemy.get_node("AI/Tactics/CoverAction")
	var wall = arena.get_node("NavigationRegion3D/Environment/CoverA")
	var collision = wall.get_node("CollisionShape3D")
	player.set_physics_process(false)
	ai.set_physics_process(false)
	player.global_position = collision.to_global(Vector3(-4, -1.1, 0))
	enemy.global_position = collision.to_global(Vector3(-1.4, -1.1, 0))
	enemy.look_at(enemy.global_position + Vector3.RIGHT)
	for frame in range(5):
		await scene.get_tree().physics_frame
	var checks := {}
	cover.selection.debug_cover_selection = false
	cover.take_cover_chance = 1.0
	ai.attack_position_uncertainty = 0.0
	cover.look_position = player.global_position
	cover.threat_origin = cover.look_position + Vector3.UP * 0.8
	checks["same_shot_has_available_cover"] = cover._choose_cover()
	cover.reset()
	cover.phase = cover.Phase.HIDE
	cover.hide_position = enemy.global_position
	cover.look_position = collision.to_global(Vector3(4, -1.1, 0))
	cover.threat_origin = cover.look_position + Vector3.UP * 0.8
	cover.active_cover_body = wall
	cover.timer = 2.0
	var health_before: float = enemy.health
	checks["hidden_from_vision_before_hit"] = not ai.perception.can_see_player()
	enemy.receive_hit(1.0, player.global_position)
	checks["actual_damage_applied"] = is_equal_approx(enemy.health, health_before - 1.0)
	checks["hit_exits_hide_immediately"] = not cover.is_active()
	checks["hit_returns_to_engagement"] = ai.state == ai.State.REPOSITION
	checks["hit_keeps_attack_memory"] = ai.last_known_position.distance_to(player.global_position) <= ai.attack_position_uncertainty + 0.01
	checks["hit_does_not_fake_visual_memory"] = not ai.has_visual_memory
	# 实际枪械先调用 receive_hit，再向所有 shot_listener 通知同一枪。
	var chest: Vector3 = enemy.global_position + Vector3.UP * 0.8
	cover.notice_shot(player.global_position + Vector3.UP * 0.8, chest)
	checks["same_shot_does_not_restart_cover"] = not cover.is_active()
	ai._physics_process(1.0 / 60.0)
	checks["next_tick_uses_main_ai"] = not cover.is_active()
	# 后续正常来弹仍有效，不能永久屏蔽掩体反应。
	for frame in range(2):
		await scene.get_tree().physics_frame
	cover.take_cover_chance = 0.0
	ai.is_alerted = false
	cover.notice_shot(player.global_position + Vector3.UP * 0.8, enemy.global_position + Vector3.UP * 0.8)
	checks["later_shot_still_alerts"] = ai.is_alerted
	# 无伤害不会强行打断躲藏。
	cover.phase = cover.Phase.HIDE
	enemy.receive_hit(0.0, player.global_position)
	checks["zero_damage_keeps_hide"] = cover.phase == cover.Phase.HIDE
	# 转移中受伤仍保留已有的冲刺和导航目标恢复行为。
	cover.phase = cover.Phase.RUN_TO_COVER
	cover.hide_position = arena.to_global(Vector3(6, 0, 8))
	cover.covering_retreat = true
	cover.damage_force_sprint_chance = 1.0
	cover.timer = 3.0
	enemy.receive_hit(1.0, player.global_position)
	checks["transfer_hit_keeps_transfer"] = cover.phase == cover.Phase.RUN_TO_COVER
	checks["transfer_hit_switches_to_sprint"] = not cover.covering_retreat
	checks["transfer_hit_restores_navigation"] = enemy.agent.target_position.is_equal_approx(cover.hide_position)
	# 各掩体短边采样收在中间25%，长边仍是原来的75%。
	for region in scene.get_tree().get_nodes_in_group("cover_region"):
		var box = region.get_node("CollisionShape3D")
		var size: Vector3 = box.shape.size
		var long_axis := Vector3.RIGHT if size.x >= size.z else Vector3.BACK
		var short_axis := Vector3.BACK if size.x >= size.z else Vector3.RIGHT
		var short_length := minf(size.x, size.z)
		var short_valid := true
		var long_extent := 0.0
		for side in [-1.0, 1.0]:
			var threat: Vector3 = box.to_global(long_axis * side * 10)
			var candidates = region.get_candidates(threat, enemy.global_position)
			short_valid = short_valid and not candidates.is_empty()
			for candidate in candidates:
				var local: Vector3 = box.to_local(candidate.hide)
				short_valid = short_valid and absf(local.dot(short_axis)) <= short_length * 0.25 * 0.5 + 0.001
				short_valid = short_valid and region.is_hiding_position(candidate.hide, threat)
			var outside: Vector3 = box.to_global(long_axis * -side * (maxf(size.x, size.z) * 0.5 + region.wall_gap + region.hide_depth * 0.5) + short_axis * short_length * 0.3 - Vector3.UP * size.y * 0.5)
			short_valid = short_valid and not region.is_hiding_position(outside, threat)
			for candidate in region.get_candidates(box.to_global(short_axis * side * 10), enemy.global_position):
				var local: Vector3 = box.to_local(candidate.hide)
				long_extent = maxf(long_extent, absf(local.dot(long_axis)))
		checks[str(region.name) + "_short_middle_25_percent"] = short_valid
		checks[str(region.name) + "_long_still_75_percent"] = is_equal_approx(long_extent, maxf(size.x, size.z) * 0.75 * 0.5)
	enemy.receive_hit(enemy.health, player.global_position)
	checks["death_stops_cover"] = enemy.is_dead and not cover.is_active()
	enemy.reset_target()
	checks["reset_clears_cover"] = not cover.is_active() and not enemy.is_dead
	return checks
