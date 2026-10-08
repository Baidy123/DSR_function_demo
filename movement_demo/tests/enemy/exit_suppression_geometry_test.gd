extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const Score = preload("res://scripts/enemy/enemy_utility_score.gd")
var failures := 0
var checks := 0
var ai
var enemy
var player
var exits
var ordinary
var cover
var scene

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	enemy = scene.get_node("Arena/Enemy")
	ai = enemy.get_node("AI")
	player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	Fixture.configure_timing(enemy)
	Fixture.set_training_action(ai, &"exit_suppression", true)
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	for body in ai.navigation_region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor": body.collision_layer = 0
	for old in get_nodes_in_group("cover_region"):
		old.collision_layer = 0
		old.remove_from_group("cover_region")
	cover = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = Vector3(22, 1.1, -2)
	cover.get_node("CollisionShape3D").shape = BoxShape3D.new()
	cover.get_node("CollisionShape3D").shape.size = Vector3(0.8, 2.2, 6)
	enemy.global_position = Vector3(24.5, 0, -2)
	player.global_position = Vector3(20.8, 0, -2)
	ai.is_alerted = true
	ai.has_visual_memory = true
	# 新归属规则要求冻结线索确实在墙后，不能仅靠近端部。
	ai.last_seen_position = Vector3(20.8, 0, -2)
	ai.last_known_position = ai.last_seen_position
	ai.utility_unseen_seconds = 0.0
	exits = ai.actions[&"exit_suppression"]
	ordinary = ai.actions[&"suppression"]
	await _sync()
	var symmetric := _costs()
	check(symmetric.size() == 2 and symmetric[1] < symmetric[0], "自身到两端等距时出口压制代价更低")
	check(_selected_suppression() == &"exit_suppression", "统一选择器在两种压制中选择等距出口封锁")
	exits.on_target_lost()
	check(exits.active and not exits.first_exit.is_empty() and not exits.second_exit.is_empty(), "开放掩体保留两个可通行出口")
	var all_at_exits := true
	for point: Vector3 in exits.first_exit + exits.second_exit:
		all_at_exits = all_at_exits and absf(point.x - 22.85) < 0.01 and absf(point.z + 2.0) >= 3.4 and absf(point.z + 2.0) <= 3.8
	check(all_at_exits, "所有目标都在身体绕出墙后的端部入口，不再使用宽扇环")
	var original_aim: Vector3 = exits.aim_point
	var original_shots: int = exits._shots_remaining
	_costs()
	check(exits.aim_point == original_aim and exits._shots_remaining == original_shots and exits.active, "评分预览不改写执行瞄准点或连射状态")
	exits.reset()
	enemy.global_position = Vector3(23.2, 0, -4.7)
	await _sync()
	var asymmetric := _costs()
	check(asymmetric.size() == 2 and asymmetric[0] < asymmetric[1], "敌人自身更靠近一端时普通压制代价更低")
	check(_selected_suppression() == &"suppression", "统一选择器在两种压制中选择近侧普通压制")
	player.global_position = Vector3(22, 0, 1.45)
	await _sync()
	var moved_player := _costs()
	check(moved_player == asymmetric, "移动隐藏玩家不改变距离评分或出口查询")
	enemy.global_position = Vector3(24.5, 0, -2)
	await _sync()
	exits.on_target_lost()
	# 墙与掩体之间仅0.55米；射线能穿过，0.7米直径身体不能通过。
	var wall = _wall(Vector3(22, 1.1, -5.65), Vector3(4, 2.2, 0.2))
	await _sync()
	check(ai.cover_selection.has_clear_line(enemy.get_shot_origin(), Vector3(22.85, 0.8, -5.45)), "窄缝中心射线仍畅通，不能仅靠射线排除")
	exits.step(0.01, false)
	check(exits.active and exits.first_exit.is_empty() and not exits.second_exit.is_empty() and exits.aim_point in exits.second_exit, "运行中窄缝堵住一端后只向另一端换点")
	exits.reset()
	var blocked := _costs()
	check(blocked.size() == 2 and blocked[0] < blocked[1], "一侧身体无法通过时普通压制胜过单侧出口压制")
	check(_selected_suppression() == &"suppression", "单侧通道受堵的评分实际改变选择器结果")
	wall.global_position.z = -6.05
	await _sync()
	exits.on_target_lost()
	check(not exits.first_exit.is_empty() and not exits.second_exit.is_empty(), "墙间隙扩大到能容纳身体和余量后恢复双端出口")
	exits.reset()
	wall.global_position.z = -5.1
	await _sync()
	check(exits.utility_available(), "一端贴墙仍可保留另一端合法候选")
	exits.on_target_lost()
	check(exits.first_exit.is_empty(), "贴墙出口不会得到射击样本")
	var other_wall = _wall(Vector3(22, 1.1, 1.1), Vector3(4, 2.2, 0.2))
	await _sync()
	exits.step(0.01, false)
	check(not exits.active and not exits.utility_available(), "两端贴墙后执行结束且出口压制退出候选")
	wall.collision_layer = 0
	other_wall.collision_layer = 0
	await _sync()
	# 出口落脚点空闲，但隐藏侧入口被障碍封住；完整身体扫掠仍必须失败。
	wall.global_position = Vector3(21.25, 1.1, -5.6)
	wall.get_node("CollisionShape3D").shape.size = Vector3(0.2, 2.2, 1.2)
	wall.collision_layer = 1
	await _sync()
	check(ai.context.is_position_free(Vector3(22, 0, -5.45)), "通道中点能站人")
	exits.on_target_lost()
	check(exits.first_exit.is_empty(), "隐藏侧入口受阻时不能把孤立落脚点当出口")
	exits.reset()
	wall.collision_layer = 0
	ai.last_seen_position = Vector3(22.8, 0, -2)
	await _sync()
	check(not exits.utility_available(), "记忆位于墙正面中部时不推断为墙后玩家出口")
	ai.last_seen_position = Vector3(20.8, 0, -2)
	# 无关掩体虽靠近记忆，但被其他实体遮住，不能取代可信目标掩体。
	var irrelevant = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(irrelevant)
	irrelevant.global_position = Vector3(22.8, 1.1, -5.8)
	irrelevant.get_node("CollisionShape3D").shape = BoxShape3D.new()
	irrelevant.get_node("CollisionShape3D").shape.size = Vector3(0.2, 2.2, 0.2)
	wall.global_position = Vector3(23.6, 1.1, -3.9)
	wall.get_node("CollisionShape3D").shape.size = Vector3(0.7, 2.2, 0.7)
	wall.collision_layer = 1
	await _sync()
	check(exits._prepare_targets(ai.last_seen_position + Vector3.UP * 0.8) and exits.target_cover == cover, "无关近墙不遮挡冻结线索时只保留实际遮挡掩体")
	irrelevant.collision_layer = 0
	irrelevant.remove_from_group("cover_region")
	wall.collision_layer = 0
	# 同时变换观察者和记忆，验证局部出口语义及世界身体尺寸。
	cover.rotation.y = 0.6
	cover.scale = Vector3(1.3, 1, 0.8)
	var box = cover.get_node("CollisionShape3D")
	enemy.global_position = box.to_global(Vector3(2.5, -1.1, 0))
	ai.last_seen_position = box.to_global(Vector3(-1.2, -1.1, 0))
	await _sync()
	check(exits._prepare_targets(ai.last_seen_position + Vector3.UP * 0.8) and not exits.first_exit.is_empty() and not exits.second_exit.is_empty(), "旋转和非均匀缩放后两端通道仍可用")
	all_at_exits = true
	for target: Vector3 in exits.first_exit + exits.second_exit:
		var local: Vector3 = box.to_local(target - Vector3.UP * 0.8)
		all_at_exits = all_at_exits and absf(local.x - (0.4 + 0.45 / 1.3)) < 0.01 and absf(local.z) > 3.0
	check(all_at_exits, "旋转缩放后目标仍在所属出口")
	cover.rotation = Vector3.ZERO
	cover.scale = Vector3.ONE
	enemy.global_position = Vector3(22, 0, -7)
	ai.last_seen_position = Vector3(22, 0, 1.8)
	await _sync()
	check(exits._prepare_targets(ai.last_seen_position + Vector3.UP * 0.8), "从短边观察时也能推断出口")
	all_at_exits = true
	for target: Vector3 in exits.first_exit + exits.second_exit:
		all_at_exits = all_at_exits and absf(target.z + 5.45) < 0.01 and absf(target.x - 22.0) > 0.8
	check(all_at_exits, "短边出口沿对应墙面两端生成，不固定使用长轴")
	cover.get_node("CollisionShape3D").disabled = true
	await _sync()
	check(not exits.utility_available(), "停用碰撞的掩体不能继续生成出口候选")
	cover.get_node("CollisionShape3D").disabled = false
	await _check_turning()
	print("EXIT SUPPRESSION GEOMETRY: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _check_turning() -> void:
	enemy.global_position = Vector3(24.5, 0, -2)
	ai.last_seen_position = Vector3(20.8, 0, -2)
	player.global_position = Vector3(20.8, 0, -2)
	await _sync()
	exits.reset()
	exits.on_target_lost()
	var target: Vector3 = exits.second_exit[0]
	enemy.look_at(target)
	enemy.has_aim = true
	enemy.aim_acquired = true
	enemy.aim_direction = (exits.first_exit[0] - enemy.get_shot_origin()).normalized()
	enemy.shot_cooldown = 0.0
	ai.context.fire.fire_pause_remaining = 0.0
	var shots: int = enemy.shot_count
	var remaining: int = exits._shots_remaining
	ai.context.fire.update(1.0 / 60.0, false, false, {"owner": &"exit_suppression", "mode": &"memory", "point": target})
	check(enemy.shot_count == shots and exits._shots_remaining == remaining, "已有瞄准锁定也不能在换边转枪途中开火或消耗每侧枪数")
	for frame in 120:
		await physics_frame
		enemy.face_direction(target - enemy.global_position, 1.0 / 60.0)
		ai.context.fire.update(1.0 / 60.0, false, false, {"owner": &"exit_suppression", "mode": &"memory", "point": target})
		if enemy.shot_count > shots: break
	check(enemy.shot_count > shots, "枪口跟上新出口后恢复真实开火")
	check(enemy.last_shot_direction.angle_to(target - enemy.get_shot_origin()) <= enemy.AIM_ACQUIRE_ANGLE + 0.001, "满准度真实子弹朝向新出口而非两出口之间")
	var maximum_us := 0
	for frame in 60:
		await physics_frame
		var started := Time.get_ticks_usec()
		_costs()
		exits._targets_available()
		maximum_us = maxi(maximum_us, Time.get_ticks_usec() - started)
	check(maximum_us < 20000, "双压制评分与执行通行复核合计小于20毫秒")
	print("EXIT GEOMETRY BUDGET: max %.3f ms" % (maximum_us / 1000.0))

func _selected_suppression() -> StringName:
	var options: Array = ai.action_selector.assess_options(ai, false).filter(func(candidate): return candidate.id in [&"suppression", &"exit_suppression"])
	return ai.action_selector.choose_option(options).get("id", &"")

func _costs() -> Array[float]:
	ai.utility_suppression_pending = true
	var result: Array[float] = []
	for action in [ordinary, exits]:
		var candidates: Array = action.collect_candidates(false)
		if candidates.is_empty(): return []
		var outcome: Dictionary = candidates[0].outcome
		result.append(Score.score_outcome(ai.context, outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss).cost)
	return result

func _wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	collision.shape.size = size
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = position
	return wall

func _sync() -> void:
	for frame in 3: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
