extends RefCounted

# 固定随机序列，将 B 放到一条真实的三维散布弹道上。
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
	c.aim_mode = c.AimMode.SPREAD_CONE
	var weapon = c.weapon.duplicate()
	weapon.min_spread_angle_degrees = 20.0
	weapon.max_spread_angle_degrees = 20.0
	c.equip_weapon(weapon)
	seed(1234)
	var direction: Vector3 = c._random_direction_in_spread_cone(Vector3.FORWARD, 20.0)
	b.position = p.position + direction * 2.8
	for i in range(5): await tree.physics_frame
	c.begin_frame(0.0, true)
	var checks := {"locked_a": c.locked_target == a}
	var a_hits: int = a.hit_count
	var b_hits: int = b.hit_count
	# 稳定度100%仍用武器最小散布，不会强制直指 A。
	c.accuracy = 1.0
	seed(1234)
	c.shoot()
	checks["ray_collides_with_b"] = c.last_shot_collider == b
	checks["aim_a_hit_b"] = b.hit_count == b_hits + 1 and a.hit_count == a_hits
	# 零散布无锁定射击：先碰墙；移开墙后只命中前方第一个靶。
	weapon.min_spread_angle_degrees = 0.0
	weapon.max_spread_angle_degrees = 0.0
	b.position = Vector3(0, 0, -3)
	wall.position = Vector3(0, 1, -2)
	for i in range(5): await tree.physics_frame
	c.begin_frame(0.0, true)
	checks["wall_breaks_lock"] = c.locked_target == null
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
	var count: int = c.shot_count
	c.shot_cooldown = 0.0
	p.is_in_dialogue = true
	c.shoot()
	checks["dialogue_blocks_fire"] = c.shot_count == count
	p.is_in_dialogue = false
	p.position = Vector3(0, 0, 5)
	for i in range(5): await tree.physics_frame
	c.begin_frame(0.0, true)
	c.shoot()
	checks["outside_zone_blocks_aim_and_fire"] = not c.is_aiming and c.shot_count == count
	randomize()
	return checks
