extends RefCounted

func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var e = scene.get_node("Arena/Enemy")
	var checks := {}
	e.player = null
	e.reset_target()
	var start: Vector3 = e.global_position
	for i in range(180): await tree.physics_frame
	checks["idle_starts_roaming"] = e.global_position.distance_to(start) > 0.5
	if not checks.idle_starts_roaming:
		return checks
	var destinations: Array[Vector3] = []
	var stayed_inside := true
	var paused := false
	for i in range(1200):
		await tree.physics_frame
		stayed_inside = stayed_inside and absf(e.position.x) < 9.0 and absf(e.position.z) < 5.0
		if e.state == e.State.PATROL and not destinations.has(e.agent.target_position):
			destinations.append(e.agent.target_position)
		if e.state == e.State.IDLE and Vector2(e.velocity.x, e.velocity.z).length() < 0.01:
			paused = true
	checks["multiple_destinations"] = destinations.size() >= 2
	checks["stays_inside_arena"] = stayed_inside
	checks["pauses_between_walks"] = paused
	e.receive_hit(1.0, e.global_position + Vector3(2, 0, 0))
	checks["attack_interrupts_patrol"] = e.state == e.State.INVESTIGATE
	e.state = e.State.SEARCH
	e.search_timer = 0.01
	for i in range(180): await tree.physics_frame
	checks["search_returns_to_patrol"] = e.state == e.State.PATROL
	e.receive_hit(1000.0)
	start = e.global_position
	for i in range(30): await tree.physics_frame
	checks["dead_does_not_patrol"] = e.global_position.is_equal_approx(start)
	e.reset_target()
	start = e.global_position
	for i in range(180): await tree.physics_frame
	checks["reset_resumes_patrol"] = not e.is_dead and e.global_position.distance_to(start) > 0.5
	return checks
