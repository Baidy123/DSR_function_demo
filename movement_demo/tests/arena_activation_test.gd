extends RefCounted

# 在独立 Main 运行中调用；通过真实 Area3D 重叠信号验证进入/离场，不手动调用区域回调。
func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var arena = scene.get_node("Arena")
	var player = scene.get_node("Player")
	var enemy = arena.get_node("Enemy")
	var ai = enemy.get_node("AI")
	var cover = enemy.get_node("AI").cover
	var checks := {}
	player.set_physics_process(false)
	ai.set_physics_process(false)
	player.position = Vector3.ZERO
	for frame in range(5):
		await tree.physics_frame
	enemy.reset_target()
	var start: Vector3 = enemy.global_position
	var pause: float = ai.patrol_pause_timer
	ai._physics_process(pause + 0.1)
	checks["outside_does_not_patrol"] = ai.state == ai.State.IDLE
	checks["outside_keeps_patrol_timer"] = is_equal_approx(ai.patrol_pause_timer, pause)
	checks["outside_keeps_position"] = enemy.global_position.is_equal_approx(start)

	enemy.reset_target()
	var chest: Vector3 = enemy.global_position + Vector3.UP * 0.8
	cover.notice_shot(chest, chest + Vector3.UP * 0.1)
	checks["outside_shot_does_not_alert"] = not ai.is_alerted
	checks["outside_shot_does_not_start_cover"] = not cover.is_active()
	enemy.reset_target()
	enemy.receive_hit(1.0, start + Vector3.RIGHT)
	checks["outside_hit_does_not_start_investigation"] = not ai.is_alerted and ai.state == ai.State.IDLE
	enemy.reset_target()

	# 在敌人旁边入场，关闭感知范围以单独检查巡逻是否解锁。
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	player.global_position = start
	for frame in range(5):
		await tree.physics_frame
	checks["entry_detected"] = arena.players_inside.has(player)
	ai._physics_process(ai.patrol_pause_seconds + 0.1)
	checks["entry_starts_patrol"] = ai.state == ai.State.PATROL
	enemy.receive_hit(10.0, player.global_position)
	checks["inside_hit_alerts_and_damages"] = ai.is_alerted and is_equal_approx(enemy.health, enemy.max_health - 10.0)

	player.position = Vector3.ZERO
	for frame in range(5):
		await tree.physics_frame
	checks["exit_resets_health_and_alert"] = is_equal_approx(enemy.health, enemy.max_health) and not ai.is_alerted
	checks["exit_restores_spawn"] = enemy.global_position.is_equal_approx(start)
	ai._physics_process(ai.patrol_pause_seconds + 0.1)
	checks["exit_stays_dormant"] = ai.state == ai.State.IDLE
	player.global_position = start
	for frame in range(5):
		await tree.physics_frame
	ai._physics_process(ai.patrol_pause_seconds + 0.1)
	checks["reentry_starts_patrol"] = ai.state == ai.State.PATROL
	return checks
