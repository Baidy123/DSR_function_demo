extends RefCounted

func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var p = scene.get_node("Player")
	var range_node = scene.get_node("CombatTest")
	var a = range_node.get_node("TargetA")
	var b = range_node.get_node("TargetB")
	var original: Transform3D = b.transform
	var original_body: Transform3D = b.get_node("Body").transform
	var checks := {}
	p.set_physics_process(false)
	p.position = Vector3(0, 0, -2)
	for i in range(6): await tree.physics_frame
	a.receive_hit(25.0)
	b.receive_hit(1000.0)
	p.position = Vector3(0, 0, 2)
	for i in range(35): await tree.physics_frame
	checks["exit_revives_test_target"] = not b.is_dead and b.health == b.max_health
	checks["exit_clears_training_count"] = a.hit_count == 0
	checks["exit_restores_collision_and_lock_group"] = not b.get_node("CollisionShape3D").disabled and b.is_in_group("combat_target")
	checks["exit_cancels_fall_animation"] = b.get_node("Body").transform.is_equal_approx(original_body)
	checks["preserves_authored_target_position"] = b.transform.is_equal_approx(original)
	p.position = Vector3(0, 0, -2)
	for i in range(6): await tree.physics_frame
	b.receive_hit(25.0)
	a.receive_hit(25.0)
	for i in range(8): await tree.physics_frame
	checks["staying_inside_does_not_reset"] = b.health == b.max_health - 25.0 and a.hit_count == 1
	p.position = Vector3(0, 0, 2)
	for i in range(6): await tree.physics_frame
	checks["second_exit_resets_again"] = b.health == b.max_health and a.hit_count == 0
	return checks
