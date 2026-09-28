extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy_fire_fixture.gd").configure_timing(enemy)
	var resource = load("res://enemy_actions/suppression.tres")
	ai.unit_type.available_actions.append(resource)
	ai.training.allowed_actions.append(resource)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", true)
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
	wall.global_position = Vector3(23, 1, -2)
	for frame in range(5): await physics_frame
	check(not action.utility_available(), "墙后没有可射目标时压制不可参选")
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
		ai.tactics.update_shooting(1.0 / 60.0, false, false)
	check(enemy.shot_count > shots, "有效压制实际开火")
	wall.collision_layer = 1
	for frame in range(3): await physics_frame
	action.step(1.0 / 60.0, false)
	check(not action.is_active(), "压制中射界失效立即交回决策")
	# 中心与一侧被挡，但另一侧仍可射：必须挑可射样本，不能等一个打不出的枪。
	box.size.z = 0.4
	action.target_radius = 1.5
	for frame in range(3): await physics_frame
	action.on_target_lost()
	check(action.is_active(), "部分目标区域可射时仍能压制")
	var all_clear := true
	for sample in range(40):
		action.on_shot_fired()
		var origin: Vector3 = enemy.get_shot_origin()
		all_clear = all_clear and ai.tactics.has_clear_firing_lane(origin, action.aim_point - origin, origin.distance_to(action.aim_point))
	check(all_clear, "压制只从实际可射目标中换点")
	action.reset()
	wall.collision_layer = 0
	for region in get_nodes_in_group("cover_region"):
		region.collision_layer = 0
		region.remove_from_group("cover_region")
	var cover = load("res://cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = Vector3(22, 1.1, -2)
	var cover_collision = cover.get_node("CollisionShape3D")
	cover_collision.shape = cover_collision.shape.duplicate()
	cover_collision.shape.size = Vector3(0.8, 2.2, 3)
	enemy.global_position = Vector3(24.5, 0, -2)
	ai.last_seen_position = Vector3(22.8, 0, -4.05)
	var exit_resource = load("res://enemy_actions/exit_suppression.tres")
	ai.unit_type.available_actions.append(exit_resource)
	ai.training.allowed_actions.append(exit_resource)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", true)
	var exits = ai.actions[&"exit_suppression"]
	for frame in range(3): await physics_frame
	exits.on_target_lost()
	check(exits.is_active(), "两端确有射界时仍可启动出口压制")
	all_clear = true
	for target: Vector3 in exits.first_exit + exits.second_exit:
		var origin: Vector3 = enemy.get_shot_origin()
		all_clear = all_clear and ai.tactics.has_clear_firing_lane(origin, target - origin, origin.distance_to(target))
	check(all_clear and not exits.first_exit.is_empty() and not exits.second_exit.is_empty(), "出口候选也统一检查完整射界")
	print("UTILITY SUPPRESSION BLOCKED: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
