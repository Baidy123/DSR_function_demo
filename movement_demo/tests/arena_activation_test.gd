extends RefCounted

# 在独立 Main 运行中调用；通过真实 Area3D 重叠信号验证进入/离场，不手动调用区域回调。
func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var arena = scene.get_node("Arena")
	var player = scene.get_node("Player")
	var enemy = arena.get_node("Enemy")
	var cover = enemy.get_node("Cover")
	var checks := {}
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	player.position = Vector3.ZERO
	for frame in range(5):
		await tree.physics_frame
	enemy.reset_target()
	var start: Vector3 = enemy.global_position
	var pause: float = enemy.patrol_pause_timer
	enemy._physics_process(pause + 0.1)
	checks["outside_does_not_patrol"] = enemy.state == enemy.State.IDLE
	checks["outside_keeps_patrol_timer"] = is_equal_approx(enemy.patrol_pause_timer, pause)
	checks["outside_keeps_position"] = enemy.global_position.is_equal_approx(start)

	enemy.reset_target()
	var chest: Vector3 = enemy.global_position + Vector3.UP * 0.8
	cover.notice_shot(chest, chest + Vector3.UP * 0.1)
	checks["outside_shot_does_not_alert"] = not enemy.is_alerted
	checks["outside_shot_does_not_start_cover"] = not cover.is_active()
	enemy.reset_target()
	enemy.receive_hit(1.0, start + Vector3.RIGHT)
	checks["outside_hit_does_not_start_investigation"] = not enemy.is_alerted and enemy.state == enemy.State.IDLE
	enemy.reset_target()

	# 在敌人旁边入场，关闭感知范围以单独检查巡逻是否解锁。
	enemy.sight_distance = 0.0
	enemy.close_awareness_radius = 0.0
	player.global_position = start
	for frame in range(5):
		await tree.physics_frame
	checks["entry_detected"] = arena.players_inside.has(player)
	enemy._physics_process(enemy.patrol_pause_seconds + 0.1)
	checks["entry_starts_patrol"] = enemy.state == enemy.State.PATROL
	enemy.receive_hit(10.0, player.global_position)
	checks["inside_hit_alerts_and_damages"] = enemy.is_alerted and is_equal_approx(enemy.health, enemy.max_health - 10.0)

	player.position = Vector3.ZERO
	for frame in range(5):
		await tree.physics_frame
	checks["exit_resets_health_and_alert"] = is_equal_approx(enemy.health, enemy.max_health) and not enemy.is_alerted
	checks["exit_restores_spawn"] = enemy.global_position.is_equal_approx(start)
	enemy._physics_process(enemy.patrol_pause_seconds + 0.1)
	checks["exit_stays_dormant"] = enemy.state == enemy.State.IDLE
	player.global_position = start
	for frame in range(5):
		await tree.physics_frame
	enemy._physics_process(enemy.patrol_pause_seconds + 0.1)
	checks["reentry_starts_patrol"] = enemy.state == enemy.State.PATROL
	return checks
