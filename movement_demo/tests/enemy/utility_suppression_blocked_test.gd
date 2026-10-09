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
	ai.context.last_seen_aim_position = player.global_position + Vector3.UP * 0.8
	ai.context.publish_suppression_evidence(&"visual_loss", player.global_position)
	var action = ai.actions[&"suppression"]
	# 先完成合法出生点验证，再模拟运行中靠近枪口的动态障碍。
	# 否则测试构造的是出生时身体已经嵌墙，敌人应保持待命。
	for frame in range(5): await physics_frame
	check(ai.context.environment_ready(), "动态堵枪口测试从合法出生点开始")
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
	# Samples cannot turn a fully blocked observed center into an inferred exit.
	box.size.z = 0.1
	action.target_radius = 1.5
	for frame in range(3): await physics_frame
	ai.context.publish_suppression_evidence(&"visual_loss", ai.last_seen_position)
	action.on_target_lost()
	check(not action.is_active(), "中心被挡时周边散布样本不能伪造可压制区域")
	check(action.collect_candidates(false).is_empty(), "大半径不会绕过冻结中心的完整硬遮挡")
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
	ai.last_seen_position = Vector3(20.8, 0, -2)
	var exits = ai.actions[&"suppression"]
	ai.last_known_position = ai.last_seen_position
	ai.context.last_seen_aim_position = ai.last_seen_position + Vector3.UP * 0.8
	ai.context.publish_suppression_evidence(&"visual_loss", ai.last_seen_position)
	for frame in range(3): await physics_frame
	var geometry: Dictionary = ai.cover_selection.suppression_geometry(ai.last_seen_position)
	check(not geometry.is_empty() and not geometry.first.is_empty() and not geometry.second.is_empty(), "实体掩体仍可提供两端通路供搜索选位")
	var removed := true
	for mode in [&"exit_sweep", &"exit_left", &"exit_right"]:
		removed = removed and exits.preview_candidate(mode).is_empty() and not exits.begin({"plan": mode}, false)
	check(removed and not exits.is_active(), "两端真实通路也不恢复出口候选和运行分支")
	options = ai.action_selector.assess_options(ai, false)
	check(not options.any(func(option): return option.id == &"suppression"), "统一候选池不再以墙后坐标或出口推断制造火力收益")
	ai.invalidate_utility()
	ai._update_utility_decision(0.5, false)
	check(ai.utility_current.get("id") != &"suppression", "正常Utility拒绝无效盲射并选择其他动作")
	var original_range: float = enemy.weapon.fire_range
	enemy.weapon.fire_range = 2.6
	check(exits.preview_candidate(&"point").is_empty() and exits.preview_candidate(&"exit_sweep").is_empty(), "冻结点超射程不能借更近出口伪造火力")
	enemy.weapon.fire_range = original_range
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
	check(ai.cover_selection.suppression_geometry(ai.last_seen_position).is_empty(), "实际遮挡墙不再提供掩体语义时共享几何不会改认邻墙")
	cover.add_to_group("cover_region")
	geometry = ai.cover_selection.suppression_geometry(ai.last_seen_position)
	check(geometry.get("body") == cover, "恢复实际遮挡墙后共享几何仅选择原归属墙")
	check(geometry.get("first", []).is_empty() != geometry.get("second", []).is_empty(), "真实实体障碍仍将共享通路限制为单侧")
	print("UTILITY SUPPRESSION BLOCKED: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
