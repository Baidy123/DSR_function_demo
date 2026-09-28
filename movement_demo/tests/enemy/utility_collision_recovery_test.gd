extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	ai.cover_selection.debug_cover_selection = false
	ai.actions[&"search"].tracking_cheat_enabled = false
	player.get_node("Health").debug_invincible = true
	# 单独检查动态身体阻挡；关掉本测试实例的掩体射界，不写回地图资源。
	for region in get_nodes_in_group("cover_region"):
		region.collision_layer = 0
		region.remove_from_group("cover_region")
	enemy.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(25.2, 0, -2)
	ai.is_alerted = true
	ai.last_known_position = Vector3(22, 0, -2)
	for f in range(5): await physics_frame
	var destination: Dictionary = {}
	for frame in range(120):
		for point: Vector3 in ai.actions[&"engage"].get_engagement_candidate_points():
			if point.distance_to(enemy.global_position) < 1.5: continue
			var trial: Dictionary = ai.actions[&"engage"].assess_engagement_point(point, ai.last_known_position)
			if trial.is_empty(): continue
			destination = trial
			break
		if not destination.is_empty(): break
		await physics_frame
	check(not destination.is_empty(), "碰撞测试具有有效导航射击目的地")
	if destination.is_empty():
		quit(1)
		return
	player.global_position = enemy.global_position.move_toward(destination.position, 1.1)
	for f in range(3): await physics_frame
	ai._start_utility_option({"id": &"engage", "destination": destination, "cost": 0.0}, true)
	var collided := false
	for f in range(240):
		await physics_frame
		var direction: Vector3 = preload("res://tests/enemy/enemy_fire_fixture.gd").tick_selected(ai, 1.0 / 60.0, true)
		enemy.move_character(direction, 1.0 / 60.0)
		for i in range(enemy.get_slide_collision_count()):
			collided = collided or enemy.get_slide_collision(i).get_collider() == player
	check(collided, "真实玩家胶囊阻挡了移动，不是模拟卡住标记")
	check(ai.utility_current.is_empty(), "移动持续无进展退出旧方案并交回决策")
	var options: Array = ai.action_selector.assess_options(ai, true)
	check(not options.any(func(o): return o.destination.get("position", Vector3.INF).distance_to(destination.position) < 0.25), "失败目的地短暂排除，不能立刻重选")
	player.global_position = Vector3(22, 0, -2)
	var start: Vector3 = enemy.global_position
	for f in range(300):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	check(not ai.utility_current.is_empty() and (enemy.global_position.distance_to(start) > 0.3 or enemy.shot_count > 0), "玩家离开后正常移动或开火，无永久卡住")
	print("UTILITY COLLISION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
