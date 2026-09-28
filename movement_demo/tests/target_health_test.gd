extends RefCounted

func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var p = scene.get_node("Player")
	var c = p.get_node("Combat")
	var training = scene.get_node("CombatTest/TargetA")
	var enemy = scene.get_node("CombatTest/TargetB")
	var checks := {"weapon_has_damage": c.weapon.get("damage") != null}
	if not checks.weapon_has_damage:
		return checks
	p.set_physics_process(false)
	p.position = Vector3(2.3, 0, -1)
	p.rotation = Vector3.ZERO
	for i in range(5): await tree.physics_frame
	c.begin_frame(0.0, true)
	checks["locks_living_test_target"] = c.locked_target == enemy
	var hp: float = enemy.health
	c.accuracy = 1.0
	c.shoot()
	checks["weapon_damage_applied"] = is_equal_approx(enemy.health, hp - c.weapon.damage)
	checks["health_label_updates"] = enemy.get_node("Label").text.contains(str(int(enemy.health)))
	var count: int = ceili(enemy.health / c.weapon.damage)
	for i in range(count):
		c.accuracy = 1.0
		c.shot_cooldown = 0.0
		c.shoot()
	c.begin_frame(0.0, true)
	checks["health_zero_and_dead"] = enemy.health == 0.0 and enemy.is_dead
	checks["dead_target_not_lockable"] = not enemy.is_in_group("combat_target") and c.locked_target != enemy
	var hits: int = enemy.hit_count
	enemy.receive_hit(100.0)
	checks["dead_ignores_more_damage"] = enemy.hit_count == hits and enemy.health == 0.0
	for i in range(30): await tree.physics_frame
	checks["fallen_visual"] = absf(enemy.get_node("Body").rotation.x) > 1.5
	checks["dead_collision_disabled"] = enemy.get_node("CollisionShape3D").disabled
	for i in range(10): training.receive_hit(1000.0)
	checks["training_counts_without_dying"] = training.hit_count == 10 and not training.is_dead and training.is_in_group("combat_target")
	# 新实例模拟重新运行：死亡和命中计数不写回资源。
	var fresh = load("res://scenes/world/combat_test.tscn").instantiate()
	scene.add_child(fresh)
	checks["fresh_test_target_full_health"] = fresh.get_node("TargetB").health == fresh.get_node("TargetB").max_health and not fresh.get_node("TargetB").is_dead
	checks["fresh_training_count_zero"] = fresh.get_node("TargetA").hit_count == 0
	fresh.queue_free()
	return checks
