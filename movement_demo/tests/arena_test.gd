extends RefCounted

func run(scene: Node) -> Dictionary:
	var checks := {}
	var arena = scene.get_node_or_null("Arena")
	checks["arena_instanced_in_main"] = arena != null
	if arena == null:
		return checks
	var tree = scene.get_tree()
	var p = scene.get_node("Player")
	var enemy = arena.get_node("Enemy")
	var region = arena.get_node("NavigationRegion3D")
	p.set_physics_process(false)
	enemy.set_physics_process(false)
	checks["navigation_baked"] = region.navigation_mesh.get_polygon_count() > 0
	enemy.position = Vector3(4, 0, -2)
	enemy.rotation.y = PI / 2.0
	p.global_position = arena.to_global(Vector3(1.5, 0, -2))
	for i in range(6): await tree.physics_frame
	checks["clear_view_detects_player"] = enemy.can_see_player()
	enemy.set_physics_process(true)
	for i in range(6): await tree.physics_frame
	checks["visible_player_is_remembered"] = enemy.last_known_position.distance_to(p.global_position) < 0.1
	var remembered: Vector3 = enemy.last_known_position
	enemy.set_physics_process(false)
	p.global_position = arena.to_global(Vector3(-4, 0, -2))
	for i in range(6): await tree.physics_frame
	checks["wall_blocks_vision"] = not enemy.can_see_player()
	enemy.set_physics_process(true)
	for i in range(6): await tree.physics_frame
	checks["hidden_player_does_not_update_memory"] = enemy.last_known_position.distance_to(remembered) < 0.1
	# 保持在竞技场内且藏在墙后；离场现在会重置敌人。
	p.global_position = arena.to_global(Vector3(-6, 0, 0))
	# 已验证隐藏位置不更新记忆；此处隔离感知，避免巡逻重新发现玩家。
	enemy.player = null
	var visited_memory := false
	var finished_search := false
	for i in range(300):
		await tree.physics_frame
		visited_memory = visited_memory or Vector2(enemy.global_position.x - remembered.x, enemy.global_position.z - remembered.z).length() < 0.8
		finished_search = finished_search or enemy.state == enemy.State.IDLE or enemy.state == enemy.State.PATROL
	checks["search_eventually_stops"] = finished_search
	checks["enemy_visits_last_seen_position"] = visited_memory
	enemy.set_physics_process(false)
	enemy.player = p
	enemy.position = Vector3(4, 0, -2)
	enemy.rotation.y = -PI / 2.0
	p.global_position = arena.to_global(Vector3(1.5, 0, -2))
	for i in range(6): await tree.physics_frame
	checks["behind_enemy_not_detected"] = not enemy.can_see_player()
	# 独立验证移动能绕过高墙，暂时移除感知引用避免改变目标。
	enemy.player = null
	var goal: Vector3 = arena.to_global(Vector3(-4, 0, -2))
	for i in range(6): await tree.physics_frame
	enemy.last_known_position = goal
	enemy.state = enemy.State.INVESTIGATE
	enemy.agent.target_position = goal
	enemy.set_physics_process(true)
	var detoured := false
	var reached_goal := false
	for i in range(480):
		await tree.physics_frame
		reached_goal = reached_goal or enemy.global_position.distance_to(goal) < 0.9
		if absf(enemy.position.z + 2.0) > 1.4:
			detoured = true
	checks["navigation_detours_around_wall"] = detoured
	checks["navigation_reaches_far_side"] = reached_goal
	enemy.receive_hit(1000.0)
	var dead_position: Vector3 = enemy.global_position
	for i in range(25): await tree.physics_frame
	checks["dead_enemy_stops_and_unlocks"] = enemy.is_dead and not enemy.is_in_group("combat_target") and enemy.global_position.distance_to(dead_position) < 0.01
	return checks
