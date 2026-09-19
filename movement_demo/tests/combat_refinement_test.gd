extends RefCounted

func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var p = scene.get_node("Player")
	var c = p.get_node("Combat")
	var checks := {}
	p.position = Vector3.ZERO
	p.rotation = Vector3.ZERO
	Input.action_press("aim")
	for i in range(5): await tree.physics_frame
	checks["outside_cannot_aim"] = not c.is_aiming
	var shots = c.shot_count
	c.shoot()
	checks["outside_cannot_fire"] = c.shot_count == shots
	p.position = Vector3(0, 0, -1)
	for i in range(8): await tree.physics_frame
	checks["inside_can_lock"] = is_instance_valid(c.locked_target)
	Input.action_press("move_right")
	Input.action_press("sprint")
	for i in range(25): await tree.physics_frame
	checks["locked_slow_speed"] = p.current_speed <= p.move_speed * 0.51
	checks["locked_no_sprint"] = not p.is_sprinting
	checks["moving_low_accuracy"] = c.accuracy <= 0.351
	Input.action_release("move_right")
	Input.action_release("sprint")
	for i in range(210): await tree.physics_frame
	checks["rest_recovers_full"] = is_equal_approx(c.accuracy, 1.0)
	c.shoot()
	var first: float = c.accuracy
	for i in range(15): await tree.physics_frame
	checks["shot_recovery_delayed"] = c.accuracy <= first + 0.001
	c.shoot()
	checks["rapid_fire_accumulates"] = c.accuracy < first - 0.2
	var low: float = c.accuracy
	Input.action_release("aim")
	for i in range(2): await tree.physics_frame
	Input.action_press("aim")
	for i in range(2): await tree.physics_frame
	checks["reaim_does_not_erase_penalty"] = c.accuracy <= low + 0.001
	for i in range(4):
		for j in range(15): await tree.physics_frame
		c.shoot()
	checks["rapid_fire_reaches_floor"] = is_equal_approx(c.accuracy, 0.1)
	var reticle = c.get_node_or_null("HUD/Reticle")
	checks["reticle_exists"] = reticle != null
	if reticle != null:
		c.accuracy = 0.2
		await tree.process_frame
		await tree.process_frame
		var large: float = reticle.radius
		c.accuracy = 1.0
		await tree.process_frame
		await tree.process_frame
		checks["reticle_shrinks"] = reticle.radius < large and reticle.visible
	var zone = scene.get_node("CombatTest/CombatZone")
	var extra = zone.duplicate()
	scene.get_node("CombatTest").add_child(extra)
	zone.monitoring = false
	for i in range(5): await tree.physics_frame
	checks["overlapping_zone_still_allows_combat"] = c.can_combat()
	extra.queue_free()
	for i in range(5): await tree.physics_frame
	checks["removed_last_zone_disables_combat"] = not c.can_combat() and not c.is_aiming
	zone.monitoring = true
	for i in range(5): await tree.physics_frame
	p.position = Vector3(0, 0, 1)
	for i in range(5): await tree.physics_frame
	checks["exit_unlocks"] = not c.is_aiming and c.locked_target == null
	if reticle != null:
		checks["exit_hides_reticle"] = not reticle.visible
	shots = c.shot_count
	c.shoot()
	checks["exit_blocks_fire"] = c.shot_count == shots
	Input.action_release("aim")
	return checks
