extends RefCounted

func run(scene: Node) -> Dictionary:
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var player = scene.get_node("Player")
	var combat = player.get_node("Combat")
	var tree := scene.get_tree()
	var cover = enemy.get_node_or_null("Cover")
	var checks := {"cover_component_exists": cover != null}
	if cover == null:
		return checks
	player.set_physics_process(false)
	enemy.combat_type = enemy.CombatType.RANGED
	cover.hide_seconds = 0.4
	cover.watch_seconds = 0.3

	# 先真正看见玩家，再让弹道从身边掠过，不能要求先扣血。
	await _place(arena, enemy, player, Vector3(4, 0, -2), Vector3(1, 0, -2))
	enemy.set_physics_process(true)
	await _wait(tree, 3)
	enemy.set_physics_process(false)
	var seen: Vector3 = enemy.last_seen_position
	player.global_position = arena.to_global(Vector3(1, 0, -1.2))
	player.rotation.y = -PI / 2.0
	await _wait(tree, 6)
	var health: float = enemy.health
	var shot_origin: Vector3 = player.global_position + Vector3.UP * 0.8
	_fire(combat)
	checks["near_miss_without_damage_triggers_cover"] = enemy.health == health and cover.is_active()
	checks["shot_does_not_overwrite_last_seen"] = enemy.last_seen_position.is_equal_approx(seen)
	if not cover.is_active():
		return checks
	checks["cover_blocks_incoming_direction"] = cover.is_hidden_at(cover.hide_position, shot_origin)
	checks["peek_has_view_of_last_seen"] = cover.has_clear_line(cover.peek_position + Vector3.UP * 0.8, seen + Vector3.UP * 0.8)
	player.global_position = arena.to_global(Vector3(-6, 0, 0))
	await _wait(tree, 6)
	enemy.set_physics_process(true)
	var reached_hide := false
	for i in range(600):
		await tree.physics_frame
		if cover.phase == cover.Phase.HIDE:
			reached_hide = true
			break
	checks["runs_to_cover"] = reached_hide
	checks["actually_hidden_at_stop"] = reached_hide and cover.is_hidden_at(enemy.global_position, shot_origin)
	var hidden_start: Vector3 = enemy.global_position
	await _wait(tree, 8)
	checks["waits_behind_cover"] = cover.phase == cover.Phase.HIDE and enemy.global_position.distance_to(hidden_start) < 0.05
	var slow_peek := false
	var watched := false
	var peek_clear := false
	var searched := false
	for i in range(600):
		await tree.physics_frame
		if cover.phase == cover.Phase.PEEK_OUT and enemy.velocity.length() > 0.1:
			slow_peek = enemy.velocity.length() <= enemy.move_speed * cover.peek_speed_multiplier + 0.1
		watched = watched or cover.phase == cover.Phase.WATCH
		if cover.phase == cover.Phase.WATCH:
			peek_clear = cover.has_clear_line(enemy.global_position + Vector3.UP * 0.8, seen + Vector3.UP * 0.8)
		searched = searched or (not cover.is_active() and enemy.state == enemy.State.SEARCH)
		if searched:
			break
	checks["slowly_peeks_out"] = slow_peek
	checks["watches_before_search"] = watched
	checks["actual_peek_position_has_clear_view"] = peek_clear
	checks["no_sighting_returns_to_search"] = searched
	checks["hidden_player_does_not_update_last_seen"] = enemy.last_seen_position.is_equal_approx(seen)

	# 原本躲在东侧，来自东侧的新子弹使旧掩体失效，应换到西侧。
	await _place(arena, enemy, player, Vector3(8.5, 0, -2.8), Vector3(12, 0, -2.8))
	enemy.has_seen_player = true
	enemy.last_seen_position = arena.to_global(Vector3(1, 0, -2))
	cover.phase = cover.Phase.HIDE
	cover.hide_position = enemy.global_position
	cover.peek_position = arena.to_global(Vector3(8.5, 0, -0.45))
	cover.look_position = enemy.last_seen_position
	cover.threat_origin = arena.to_global(Vector3(1, 0.8, -2))
	cover.timer = 3.0
	player.rotation.y = PI / 2.0
	_fire(combat)
	checks["new_attack_direction_moves_to_new_cover"] = cover.phase == cover.Phase.RUN_TO_COVER and cover.hide_position.x < arena.global_position.x + 7.0
	checks["direct_hit_also_triggers_cover"] = enemy.health < enemy.max_health and cover.is_active()

	# 墙前结束的真实弹道不能隔墙触发警戒区。
	await _place(arena, enemy, player, Vector3(8.4, 0, -2.8), Vector3(4, 0, -2.8))
	cover.shot_radius = 2.0
	player.rotation.y = -PI / 2.0
	_fire(combat)
	checks["wall_stops_suppression"] = not cover.is_active() and enemy.health == enemy.max_health
	cover.shot_radius = 1.5

	# 远处子弹不触发；近战沿用原行为。
	await _place(arena, enemy, player, Vector3(4, 0, -2), Vector3(1, 0, 1))
	player.rotation.y = -PI / 2.0
	_fire(combat)
	checks["distant_shot_ignored"] = not cover.is_active()
	await _place(arena, enemy, player, Vector3(4, 0, -2), Vector3(1, 0, -1.2))
	enemy.combat_type = enemy.CombatType.MELEE
	player.rotation.y = -PI / 2.0
	_fire(combat)
	checks["melee_does_not_enter_cover_cycle"] = not cover.is_active()
	enemy.combat_type = enemy.CombatType.RANGED

	# 没有标记掩体时仍能警觉，但不会卡在躲藏状态。
	var points = arena.get_node("CoverPositions")
	points.name = "UnavailableCoverPositions"
	_fire(combat)
	checks["no_cover_falls_back_to_alert"] = not cover.is_active() and enemy.is_alerted
	points.name = "CoverPositions"
	_fire(combat)
	checks["can_reenter_cover_cycle"] = cover.is_active()
	enemy.receive_hit(1000.0)
	checks["death_cancels_cover"] = enemy.is_dead and not cover.is_active()
	player.global_position = Vector3(9, 0, 0)
	await _wait(tree, 6)
	checks["exit_resets_cover_and_memory"] = not enemy.is_dead and not cover.is_active() and not enemy.has_seen_player and enemy.last_seen_position.is_equal_approx(enemy.global_position)
	return checks


func _fire(combat: Node) -> void:
	var aim_rotation: Vector3 = combat.player.visual.global_rotation
	combat.begin_frame(0.0, true)
	# 测试指定弹道方向，避免锁定自动转向把刻意打偏的子弹变成命中。
	combat.player.visual.global_rotation = aim_rotation
	combat.locked_target = null
	combat.shot_cooldown = 0.0
	combat.shoot()


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
