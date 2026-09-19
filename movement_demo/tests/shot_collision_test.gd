extends RefCounted

# 固定随机序列，仅用于让 B 恰好位于本发偏转弹道上。
func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var p = scene.get_node("Player")
	var c = p.get_node("Combat")
	var a = scene.get_node("CombatTest/TargetA")
	var b = scene.get_node("CombatTest/TargetB")
	var wall = scene.get_node("CombatTest/Cover")
	p.set_physics_process(false)
	p.position = Vector3(0, 0, -1)
	p.rotation = Vector3.ZERO
	a.position = Vector3(0, 0, -4.5)
	wall.position = Vector3(7, 1, -2)
	seed(1234)
	randf() # 是否瞄准中心的判定。
	var angle: float = randf_range(8.0, 20.0)
	if randf() < 0.5:
		angle = -angle
	var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
	b.position = p.position + direction * 2.8
	for i in range(5): await tree.physics_frame
	c.begin_frame(0.0, true)
	var checks := {"locked_a": c.locked_target == a}
	var a_hits = a.hit_count
	var b_hits = b.hit_count
	c.accuracy = 0.0
	seed(1234)
	c.shoot()
	checks["ray_collides_with_b"] = c.last_shot_collider == b
	checks["aim_a_hit_b"] = b.hit_count == b_hits + 1 and a.hit_count == a_hits
	# 无锁定直线射击也应先碰墙，不能给墙后的靶子命中。
	b.position = Vector3(0, 0, -3)
	wall.position = Vector3(0, 1, -2)
	for i in range(5): await tree.physics_frame
	c.begin_frame(0.0, true)
	c.shot_cooldown = 0.0
	b_hits = b.hit_count
	c.shoot()
	checks["wall_stops_shot"] = c.last_shot_collider == wall and b.hit_count == b_hits and a.hit_count == a_hits
	wall.position = Vector3(7, 1, -2)
	for i in range(5): await tree.physics_frame
	c.locked_target = null
	c.shot_cooldown = 0.0
	c.shoot()
	checks["first_target_only"] = c.last_shot_collider == b and b.hit_count == b_hits + 1 and a.hit_count == a_hits
	randomize()
	return checks
