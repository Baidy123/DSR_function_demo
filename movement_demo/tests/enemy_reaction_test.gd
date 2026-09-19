extends RefCounted

func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var arena = scene.get_node("Arena")
	var e = arena.get_node("Enemy")
	var p = scene.get_node("Player")
	var c = p.get_node("Combat")
	var checks := {}
	p.set_physics_process(false)
	e.set_physics_process(false)
	e.position = Vector3(4, 0, -2)
	e.rotation.y = PI / 2.0
	p.global_position = arena.to_global(Vector3(5.5, 0, -2))
	for i in range(6): await tree.physics_frame
	checks["nearby_behind_detected"] = e.can_see_player()
	checks["reaction_and_reset_available"] = e.has_method("_investigate_attack") and e.has_method("reset_target")
	if not checks.reaction_and_reset_available:
		return checks
	p.global_position = arena.to_global(Vector3(7, 0, -2))
	p.rotation.y = PI / 2.0
	for i in range(6): await tree.physics_frame
	checks["distant_behind_not_seen"] = not e.can_see_player()
	c.begin_frame(0.0, true)
	c.accuracy = 1.0
	c.shoot()
	checks["actual_shot_triggers_investigation"] = e.state == e.State.INVESTIGATE and e.health == e.max_health - c.weapon.damage
	var remembered: Vector3 = e.last_known_position
	var error: float = Vector2(remembered.x - p.global_position.x, remembered.z - p.global_position.z).length()
	checks["approximate_attack_position"] = error > 0.01 and error <= e.attack_position_uncertainty + 0.01
	# 玩家隐藏到高墙后，但不离场，以免触发刷新。
	p.global_position = arena.to_global(Vector3(-4, 0, -2))
	for i in range(6): await tree.physics_frame
	var start: Vector3 = e.global_position
	e.set_physics_process(true)
	for i in range(50): await tree.physics_frame
	checks["moves_toward_attack_area"] = e.global_position.distance_to(remembered) < start.distance_to(remembered) - 0.5
	checks["does_not_track_hidden_attacker"] = e.last_known_position.is_equal_approx(remembered)
	e.set_physics_process(false)
	# 高墙两侧距离在警戒半径内，仍不能透视。
	e.position = Vector3(-0.2, 0, -1)
	e.rotation.y = -PI / 2.0
	p.global_position = arena.to_global(Vector3(-1.8, 0, -1))
	for i in range(6): await tree.physics_frame
	checks["nearby_wall_blocks_awareness"] = not e.can_see_player()
	e.receive_hit(1000.0)
	p.global_position = Vector3(9, 0, 0)
	for i in range(30): await tree.physics_frame
	checks["exit_revives_and_restores_spawn"] = not e.is_dead and e.health == e.max_health and e.transform.is_equal_approx(e.initial_transform)
	checks["exit_resets_ai_and_collision"] = e.state == e.State.IDLE and e.is_in_group("combat_target") and not e.get_node("CollisionShape3D").disabled
	checks["exit_restores_visuals"] = e.get_node("FrontMarker").visible and e.get_node("Body").transform.is_equal_approx(e.initial_body_transform)
	# 再次进入、受伤、离开，不必死亡也能刷新。
	p.global_position = arena.to_global(Vector3(-6, 0, 0))
	for i in range(6): await tree.physics_frame
	e.receive_hit(25.0)
	p.global_position = Vector3(9, 0, 0)
	for i in range(6): await tree.physics_frame
	checks["repeat_exit_resets_injury"] = e.health == e.max_health
	return checks
