extends RefCounted

# 在新启动的 Main 中调用 run(scene)，检查完成后停止游戏。
func run(scene: Node) -> Dictionary:
	var tree := scene.get_tree()
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var player = scene.get_node("Player")
	var checks := {}
	player.set_physics_process(false)

	# 开阔地：已经处于合适距离时应站定，而不是继续贴脸。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(5, 0, 0))
	enemy.combat_type = enemy.CombatType.RANGED
	var start: Vector3 = enemy.global_position
	checks["fixture_clear_view"] = enemy.can_see_player()
	enemy.set_physics_process(true)
	await _wait(tree, 90)
	checks["holds_clear_position"] = _distance(enemy.global_position, start) < 0.15
	checks["holds_facing_player"] = (-enemy.global_basis.z).dot((player.global_position - enemy.global_position).normalized()) > 0.9

	# 太远时接近，但应在远程距离内停止。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(8, 0, 0))
	enemy.set_physics_process(true)
	await _wait(tree, 240)
	var distance := _distance(enemy.global_position, player.global_position)
	checks["approaches_to_ranged_distance"] = distance >= 4.0 and distance <= 6.0
	start = enemy.global_position
	await _wait(tree, 45)
	checks["does_not_oscillate_at_position"] = _distance(enemy.global_position, start) < 0.15

	# 太近时后退，后退过程中仍然看向玩家。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(2, 0, 0))
	enemy.set_physics_process(true)
	await _wait(tree, 90)
	checks["retreats_when_approached"] = _distance(enemy.global_position, player.global_position) > 2.8
	checks["retreat_keeps_facing_threat"] = (-enemy.global_basis.z).dot((player.global_position - enemy.global_position).normalized()) > 0.85

	# 已经站定后，玩家逼近也应重新选位。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(5, 0, 0))
	enemy.set_physics_process(true)
	await _wait(tree, 10)
	player.global_position = arena.to_global(Vector3(2, 0, 0))
	await _wait(tree, 90)
	checks["holding_enemy_reacts_to_approach"] = _distance(enemy.global_position, player.global_position) > 2.8

	# 当前导航层无可达点：近处不能回退成冲向玩家。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(2, 0, 0))
	var original_layers: int = enemy.agent.navigation_layers
	enemy.agent.navigation_layers = 2
	start = enemy.global_position
	enemy.set_physics_process(true)
	await _wait(tree, 60)
	checks["no_retreat_route_stays_put"] = _distance(enemy.global_position, start) < 0.1
	checks["no_retreat_route_does_not_target_player"] = _distance(enemy.agent.target_position, player.global_position) > 1.5
	enemy.set_physics_process(false)
	enemy.agent.navigation_layers = original_layers

	# 候选点的静态碰撞检查不能间接感知墙后玩家。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(-6, 0, 0))
	var hidden_point: Vector3 = arena.to_global(Vector3(-7, 0, 5))
	var was_free: bool = enemy._ranged_point_is_free(hidden_point)
	player.global_position = hidden_point
	await _wait(tree, 6)
	checks["fixture_candidate_hides_player"] = was_free and not enemy.can_see_player()
	checks["hidden_body_does_not_change_candidate"] = enemy._ranged_point_is_free(hidden_point) == was_free

	# 高墙隔开敌人和攻击来源；选位必须绕到有观察角度的位置。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(-6, 0, 0))
	checks["fixture_wall_blocks_view"] = not enemy.can_see_player()
	enemy.attack_position_uncertainty = 0.0
	enemy.receive_hit(1.0, arena.to_global(Vector3(-5, 0, 0)))
	var remembered: Vector3 = enemy.last_known_position
	enemy.set_physics_process(true)
	await _wait(tree, 8)
	var destination: Vector3 = enemy.agent.target_position
	distance = _distance(destination, remembered)
	checks["chooses_offset_observation_position"] = distance >= 4.0 and distance <= 6.1
	checks["observation_position_has_clear_ray"] = _clear_ray(enemy, player, destination, remembered)
	checks["observation_destination_at_floor_height"] = absf(destination.y - arena.global_position.y) < 0.1
	var region = arena.get_node("NavigationRegion3D")
	var projected: Vector3 = NavigationServer3D.region_get_closest_point(region.get_rid(), destination)
	var path := NavigationServer3D.map_get_path(enemy.agent.get_navigation_map(), enemy.global_position, projected, true, enemy.agent.navigation_layers)
	checks["observation_position_is_reachable"] = not path.is_empty() and path[path.size() - 1].distance_to(projected) < 0.5
	# 玩家还在墙后换了位置，不应改变敌人的记忆或选位目标。
	player.global_position = arena.to_global(Vector3(-6, 0, 2))
	await _wait(tree, 25)
	checks["hidden_movement_does_not_update_memory"] = enemy.last_known_position.is_equal_approx(remembered)
	checks["hidden_movement_does_not_retarget"] = enemy.agent.target_position.is_equal_approx(destination)
	enemy.player = null
	var went_around_wall := false
	var started_search := false
	for i in range(600):
		await tree.physics_frame
		went_around_wall = went_around_wall or absf(enemy.position.z) > 2.5
		started_search = started_search or enemy.state == enemy.State.SEARCH
		if started_search:
			break
	checks["moves_around_wall"] = went_around_wall
	checks["empty_observation_position_starts_search"] = started_search

	# 看见后失去视野：保留最后目击位置；搜索结束能解除警戒。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(5, 0, 0))
	enemy.set_physics_process(true)
	await _wait(tree, 6)
	remembered = enemy.last_known_position
	player.global_position = arena.to_global(Vector3(-6, 0, 0))
	await _wait(tree, 15)
	checks["lost_sight_preserves_last_seen"] = enemy.last_known_position.is_equal_approx(remembered)
	enemy.player = null
	enemy._begin_search()
	enemy.search_timer = 0.01
	await _wait(tree, 3)
	checks["search_expires_and_clears_alert"] = not enemy.is_alerted and not enemy.has_seen_player

	# 近战仍走向玩家；分类不能破坏死亡和刷新。
	await _place(arena, enemy, player, Vector3(0, 0, 0), Vector3(5, 0, 0))
	enemy.combat_type = enemy.CombatType.MELEE
	enemy.set_physics_process(true)
	await _wait(tree, 180)
	checks["melee_still_approaches"] = _distance(enemy.global_position, player.global_position) < 2.5
	enemy.combat_type = enemy.CombatType.RANGED
	enemy.receive_hit(1000.0)
	start = enemy.global_position
	await _wait(tree, 20)
	checks["death_stops_and_unlocks"] = enemy.is_dead and _distance(enemy.global_position, start) < 0.01 and not enemy.is_in_group("combat_target")
	enemy.set_physics_process(false)
	player.global_position = Vector3(9, 0, 0)
	await _wait(tree, 6)
	checks["exit_resets_health_position_and_type"] = not enemy.is_dead and enemy.health == enemy.max_health and enemy.transform.is_equal_approx(enemy.initial_transform) and enemy.combat_type == enemy.CombatType.RANGED
	checks["exit_clears_alert_and_restores_collision"] = not enemy.is_alerted and enemy.is_in_group("combat_target") and not enemy.get_node("CollisionShape3D").disabled
	return checks


func _place(arena: Node3D, enemy: CharacterBody3D, player: Node3D, enemy_position: Vector3, player_position: Vector3) -> void:
	enemy.set_physics_process(false)
	enemy.reset_target()
	enemy.player = player
	enemy.position = enemy_position
	enemy.velocity = Vector3.ZERO
	enemy.agent.target_position = enemy.global_position
	player.global_position = arena.to_global(player_position)
	enemy.look_at(player.global_position)
	await _wait(arena.get_tree(), 6)


func _wait(tree: SceneTree, frames: int) -> void:
	for i in range(frames):
		await tree.physics_frame


func _distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clear_ray(enemy: CharacterBody3D, player: CollisionObject3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.8, to + Vector3.UP * 0.8, 1, [enemy.get_rid(), player.get_rid()])
	query.hit_from_inside = true
	return enemy.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
