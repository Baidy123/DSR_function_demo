extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	ai.cover_selection.debug_attack_points = false
	enemy.debug_shooting = false
	enemy.weapon = enemy.weapon.duplicate()
	# 角度参数不再影响敌人；实际偏射沿用旧概率模式8～20度。
	enemy.weapon.max_spread_angle_degrees = 12.0
	enemy.global_position = Vector3(17.68982, 0, -1.900597)
	var wall = scene.get_node("Arena/NavigationRegion3D/Environment/CoverA")
	var target := Vector3(16.8408, 0.8, 5.551192)
	player.global_position = Vector3(20, 0, -3)
	for frame in range(20):
		await physics_frame
	var selection = ai.cover_selection
	var origin: Vector3 = enemy.get_shot_origin()
	var direction: Vector3 = origin.direction_to(target)
	_check(selection.has_clear_line(origin, target), "复现站位中心射线通畅")
	enemy._shot_rng.seed = 632
	var wall_hits := 0
	for index in range(500):
		var ray: Vector3 = enemy._random_shot_direction(direction, 0.0)
		var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(selection._ray_query(origin, origin + ray * origin.distance_to(target)))
		if hit.get("collider") == wall:
			wall_hits += 1
	print("复现：中心射线畅通，但500次散布有", wall_hits, "次打中自身掩体")
	_check(wall_hits > 0, "复现散布打中身旁长墙")
	_check(not selection.assess_attack_point(enemy.global_position, wall, target, target).usable, "拒绝容易擦墙的架枪站位")
	var known := Vector3(19.92596, 0.8, -4.2821)
	var usable := 0
	var unsafe := 0
	var exposed := 0
	var firing_fixture := {}
	for region in get_nodes_in_group("cover_region"):
		if not ai.navigation_region.is_ancestor_of(region):
			continue
		for point in region.get_attack_candidates():
			var assessment: Dictionary = selection.assess_attack_point(point, region, known, known)
			if not assessment.usable:
				continue
			usable += 1
			exposed += int(is_zero_approx(assessment.protection))
			var muzzle: Vector3 = point + Vector3.UP * 0.8
			if firing_fixture.is_empty() and muzzle.distance_to(known) < 7.5:
				for turn in [-25.0, 25.0]:
					var lagged: Vector3 = muzzle.direction_to(known).rotated(Vector3.UP, deg_to_rad(turn))
					if not selection.has_clear_shot_cone(muzzle, lagged, enemy.get_max_shot_deviation_degrees(), muzzle.distance_to(known), region):
						firing_fixture = {"point": point, "cover": region, "aim": lagged}
			for shot in range(100):
				var ray: Vector3 = enemy._random_shot_direction(muzzle.direction_to(known), 0.0)
				var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(selection._ray_query(muzzle, muzzle + ray * muzzle.distance_to(known)))
				if hit.get("collider") == region:
					unsafe += 1
					if unsafe <= 3:
						print("遗漏：", region.name, " 点=", point, " 射线=", ray, " 碰撞=", hit.position)
	print("可用架枪点=", usable, "，散布命中所属掩体=", unsafe)
	_check(usable > 0, "留出余量后仍有墙角架枪位置")
	_check(unsafe == 0, "合格架枪点最大散布抽样不打所属墙")
	_check(exposed > 0, "安全射界允许身体无遮挡的墙角站位")
	enemy.weapon.min_spread_angle_degrees = 12.0
	enemy.weapon.max_spread_angle_degrees = 0.0
	_check(not selection.assess_attack_point(enemy.global_position, wall, target, target).usable, "旧角度参数不改变概率射击的避墙范围")
	enemy.weapon.min_spread_angle_degrees = 4.0
	enemy.weapon.max_spread_angle_degrees = 12.0
	_check(not firing_fixture.is_empty(), "存在站位合格但枪口仍朝墙的跟枪复现")
	if not firing_fixture.is_empty():
		enemy.global_position = firing_fixture.point
		player.global_position = known - Vector3.UP * 0.8
		player.get_node("Health").debug_invincible = true
		enemy.look_at(player.global_position)
		for frame in range(3):
			await physics_frame
		ai.state = ai.State.HOLD_POSITION
		ai.tactics.attack_position.phase = ai.tactics.attack_position.Phase.HOLD
		ai.tactics.attack_position.active_cover = firing_fixture.cover
		ai.tactics.fire_reaction_seconds = 0.0
		ai.tactics.fire_stability_target = 0.0
		ai.tactics.fire_pause_remaining = 0.0
		enemy.aim_turn_speed_degrees = 0.0
		enemy.has_aim = true
		enemy.aim_acquired = true
		enemy.aim_direction = firing_fixture.aim
		enemy.shot_cooldown = 0.0
		enemy.weapon_stability = 0.0
		var shots: int = enemy.shot_count
		_check(ai.perception.can_see_player() and enemy.can_fire(), "复现排除视野或枪械冷却阻止开火")
		ai.tactics.update_shooting(0.0, true, false)
		_check(enemy.shot_count == shots, "架枪枪口还没转出墙面时暂缓开火")
		enemy.aim_direction = enemy.get_shot_origin().direction_to(known)
		enemy.weapon_stability = 1.0
		ai.tactics.update_shooting(0.1, true, false)
		_check(enemy.shot_count == shots + 1, "枪口转出墙面后恢复实际射击")
	scene.free()
	quit(0 if failures == 0 else 1)
