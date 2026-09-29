extends SceneTree

var failures := 0
var checks := 0

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
	var resource = load("res://resources/enemy/actions/suppression.tres")

	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, resource.action_id, true)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", true)
	ai.cover_selection.debug_cover_selection = false
	player.get_node("Health").debug_invincible = true
	enemy.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(22, 0, -2)
	enemy.look_at(player.global_position)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = player.global_position
	ai.last_known_position = player.global_position
	var action = ai.actions[&"suppression"]
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 2.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = Vector3(23.75, 1, -2)
	for frame in range(5): await physics_frame
	check(not action.utility_available(), "枪口前近墙堵住所有方向时压制不可参选")
	action.on_target_lost()
	check(not action.is_active(), "直接执行也拒绝完全被挡住的压制")
	action.reset()
	ai.utility_suppression_pending = true
	var options: Array = ai.action_selector.assess_options(ai, false)
	check(not options.any(func(o): return o.id == &"suppression"), "统一候选池排除零有效火力压制")
	wall.collision_layer = 0
	for frame in range(3): await physics_frame
	check(action.utility_available(), "射界打开后压制仍可参选")
	action.on_target_lost()
	check(action.is_active(), "可射区域可以正常启动压制")
	var shots: int = enemy.shot_count
	for frame in range(90):
		await physics_frame
		action.step(1.0 / 60.0, false)
		enemy.face_direction(action.aim_point - enemy.global_position, 1.0 / 60.0)
		ai.context.fire.update(1.0 / 60.0, false, false, {"owner": &"suppression", "mode": &"memory", "point": action.aim_point})
	check(enemy.shot_count > shots, "有效压制实际开火")
	wall.collision_layer = 1
	for frame in range(3): await physics_frame
	action.step(1.0 / 60.0, false)
	check(not action.is_active(), "压制中射界失效立即交回决策")
	# 中心与一侧被挡，但另一侧仍可射：必须挑可射样本，不能等一个打不出的枪。
	box.size.z = 0.1
	action.target_radius = 1.5
	for frame in range(3): await physics_frame
	action.on_target_lost()
	check(action.is_active(), "部分目标区域可射时仍能压制")
	var all_clear := true
	for sample in range(40):
		action.on_shot_fired()
		var origin: Vector3 = enemy.get_shot_origin()
		all_clear = all_clear and ai.context.fire.has_clear_suppression_lane(origin, action.aim_point - origin, origin.distance_to(action.aim_point))
	check(all_clear, "压制只从实际可射目标中换点")
	action.reset()
	wall.collision_layer = 0
	for region in get_nodes_in_group("cover_region"):
		region.collision_layer = 0
		region.remove_from_group("cover_region")
	var cover = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = Vector3(22, 1.1, -2)
	var cover_collision = cover.get_node("CollisionShape3D")
	cover_collision.shape = cover_collision.shape.duplicate()
	cover_collision.shape.size = Vector3(0.8, 2.2, 3)
	enemy.global_position = Vector3(24.5, 0, -2)
	ai.last_seen_position = Vector3(22.8, 0, -4.05)
	var exit_resource = load("res://resources/enemy/actions/exit_suppression.tres")

	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, exit_resource.action_id, true)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", true)
	var exits = ai.actions[&"exit_suppression"]
	for frame in range(3): await physics_frame
	exits.on_target_lost()
	check(exits.is_active(), "两端确有射界时仍可启动出口压制")
	all_clear = true
	for target: Vector3 in exits.first_exit + exits.second_exit:
		var origin: Vector3 = enemy.get_shot_origin()
		all_clear = all_clear and ai.context.fire.has_clear_suppression_lane(origin, target - origin, origin.distance_to(target)) and ai.cover_selection.has_clear_line(origin,target)
	check(all_clear and not exits.first_exit.is_empty() and not exits.second_exit.is_empty(), "出口检查枪口与中心射线，不要求整个散布避开目标墙")
	exits.reset()
	ai.last_known_position = ai.last_seen_position
	ai.utility_suppression_pending = true
	ai.utility_unseen_seconds = 0.0
	options = ai.action_selector.assess_options(ai, false)
	var ordinary: Array = options.filter(func(o): return o.id == &"suppression")
	var targeted: Array = options.filter(func(o): return o.id == &"exit_suppression")
	check(not ordinary.is_empty() and not targeted.is_empty(), "普通和出口压制同时有真实有效候选")
	check(not ordinary.is_empty() and not targeted.is_empty() and targeted[0].cost < ordinary[0].cost, "可信出口封锁收益打破与普通压制的同分")
	ai.invalidate_utility()
	ai._update_utility_decision(0.5, false)
	check(ai.utility_current.get("id") == &"exit_suppression", "统一选择器实际选择出口压制")
	shots = enemy.shot_count
	for frame in range(100):
		await physics_frame
		var output: Dictionary = exits.tick(1.0 / 60.0, false)
		enemy.face_direction(output.facing, 1.0 / 60.0)
		ai.context.fire.update(1.0 / 60.0, false, false, output.fire)
	check(enemy.shot_count > shots, "选中的出口压制实际打出子弹")
	var fresh: float = exits.information_retention()
	ai.utility_unseen_seconds = 20.0
	check(exits.information_retention() < fresh * 0.1, "出口推断随失视时间衰减，不永久压制旧位置")
	ai._cancel_utility_execution()
	# 最近的小掩体被前景墙遮住，较远的原掩体仍有一端可射。
	var nearer = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(nearer)
	nearer.global_position = Vector3(22.8, 1.1, -4.35)
	nearer.attack_inner_radius = 0.3
	nearer.attack_outer_radius = 0.45
	var nearer_collision = nearer.get_node("CollisionShape3D")
	nearer_collision.shape = nearer_collision.shape.duplicate()
	nearer_collision.shape.size = Vector3(0.2, 2.2, 0.2)
	wall.collision_layer = 1
	box.size = Vector3(0.8, 2.0, 0.8)
	wall.global_position = Vector3(23.65, 1, -3.17)
	cover.remove_from_group("cover_region")
	for frame in range(3): await physics_frame
	var center: Vector3 = ai.last_seen_position + Vector3.UP * 0.8
	check(not exits._prepare_targets(center), "最近掩体的两个出口确实被前景障碍挡住")
	cover.add_to_group("cover_region")
	check(exits._prepare_targets(center) and exits.target_cover == cover, "最近掩体不可射时继续选择其他可信邻近掩体")
	check(exits.first_exit.is_empty() != exits.second_exit.is_empty(), "只露出一侧出口时仍保留封锁方案")
	var original_range: float = enemy.weapon.fire_range
	# 新出口取身体能绕出的入口，射程仍位于真实出口与记忆中心之间。
	enemy.weapon.fire_range = 2.6
	check(enemy.get_shot_origin().distance_to(center) > enemy.weapon.fire_range and exits.utility_available(), "记忆中心超射程但实际出口可射时仍可参选")
	exits.on_target_lost()
	check(exits.is_active() and enemy.get_shot_origin().distance_to(exits.aim_point) <= enemy.weapon.fire_range, "执行阶段同样按实际出口射程启动")
	exits.reset()
	enemy.weapon.fire_range = 0.1
	check(not exits.utility_available(), "所有实际出口超射程仍不能参选")
	enemy.weapon.fire_range = original_range
	print("UTILITY SUPPRESSION BLOCKED: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
