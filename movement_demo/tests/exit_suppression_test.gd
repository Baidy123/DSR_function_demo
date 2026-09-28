extends SceneTree

var scene: Node
var enemy
var ai
var player
var action
var checks := {}
var cover: StaticBody3D
const ENEMY_POSITION := Vector3(24.5, 0, -2)
const SEEN_POSITION := Vector3(22.8, 0, -4.05)
const HIDDEN_POSITION := Vector3(21, 0, -2)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	enemy = scene.get_node("Arena/Enemy")
	ai = enemy.get_node("AI")
	player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	action = ai.tactics.exit_suppression
	_check("出口压制具有独立动作节点", action != null)
	if action == null:
		_finish()
		return
	_check("出口压制继承基础压制实现", action.get_script().get_base_script() == ai.tactics.area_suppression.get_script())
	var default_training = load("res://enemy_training.gd").new()
	_check("出口压制默认未列入训练名单", not default_training.allows_action(&"exit_suppression"))
	default_training.free()
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	player.get_node("Health").debug_invincible = true
	cover = load("res://cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = Vector3(22, 1.1, -2)
	var collision = cover.get_node("CollisionShape3D")
	collision.shape = collision.shape.duplicate()
	collision.shape.size = Vector3(0.8, 2.2, 3)
	var mesh = cover.get_node("Mesh")
	mesh.mesh = mesh.mesh.duplicate()
	mesh.mesh.size = collision.shape.size
	await _prepare_visible()
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", false)
	await _hide()
	_check("未掌握出口压制时使用普通压制", ai.tactics.area_suppression.is_active() and not action.is_active())
	await _prepare_visible()
	_check("出口测试真实目击玩家", ai.was_seeing_player)
	var memory: Vector3 = ai.last_seen_position
	await _hide()
	_check("玩家确实躲到掩体后失视", not ai.perception.can_see_player())
	_check("条件满足选择出口压制", action.is_active() and ai.tactics.suppression == action)
	_check("两种压制不会同时运行", not ai.tactics.area_suppression.is_active())
	_check("根据最后目击邻近位置选择正确掩体", action.target_cover == cover)
	_check("两个出口均有可射击候选", not action.first_exit.is_empty() and not action.second_exit.is_empty())
	if not action.is_active():
		_finish()
		return
	var points_valid := true
	var samples = cover.get_attack_candidates()
	for target in action.first_exit + action.second_exit:
		var ground: Vector3 = target - Vector3.UP * 0.8
		var is_sample := false
		for sample in samples:
			if sample.is_equal_approx(ground):
				is_sample = true
				break
		points_valid = points_valid and is_sample and ai.cover_selection.has_clear_line(enemy.get_shot_origin(), target) and enemy.get_shot_origin().distance_to(target) <= enemy.weapon.fire_range
	_check("出口瞄准点复用墙角区域且射界射程合格", points_valid)
	seed(624)
	var was_first: bool = action.first_exit.has(action.aim_point)
	var run_length := 0
	var lengths: Array[int] = []
	for sample_index in range(200):
		run_length += 1
		action.on_shot_fired()
		var is_first: bool = action.first_exit.has(action.aim_point)
		if was_first != is_first:
			# 进入测试前真实AI可能已开了一枪，第一段不是完整的换边周期。
			if sample_index > 5:
				lengths.append(run_length)
			run_length = 0
			was_first = is_first
	_check("每侧实际射击2到5枪才换边", lengths.size() > 20 and lengths.all(func(n): return n >= 2 and n <= 5))
	_check("每侧枪数随机变化并可出现2、3、5枪", lengths.has(2) and lengths.has(3) and lengths.has(5))
	var remaining_shots: int = action._shots_remaining
	var unchanged_aim: Vector3 = action.aim_point
	enemy.shot_cooldown = 10.0
	ai.tactics.update_shooting(0.01, false, false)
	_check("冷却中的开火尝试不消耗本侧枪数或换边", action._shots_remaining == remaining_shots and action.aim_point == unchanged_aim)
	enemy.shot_cooldown = 0.0
	var center: Vector3 = action.target_center
	player.global_position = Vector3(21, 0, -2.5)
	var shots: int = enemy.shot_count
	var start: Vector3 = enemy.global_position
	for frame in range(90):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	_check("出口压制实际开火", enemy.shot_count > shots)
	_check("出口压制保持原地", enemy.global_position.distance_to(start) < 0.02)
	_check("出口目标不追踪墙后玩家", action.target_cover == cover and action.target_center == center and ai.last_seen_position == memory)
	_check("出口压制也使用3到5秒计时", action.remaining >= 1.3 and action.remaining < 3.6)
	# 能力撤回立即停止，而不是继续执行高训练动作。
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", false)
	ai._physics_process(0.02)
	_check("运行中关闭高级能力退出出口压制", not action.is_active())
	await _prepare_visible()
	await _hide()
	ai.cover.take_cover_chance = 0.0
	enemy.receive_hit(1.0, HIDDEN_POSITION)
	_check("出口压制中弹同样停止并找掩体", not action.is_active() and ai.cover.is_active())
	await _prepare_visible()
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", false)
	await _hide()
	_check("普通压制关闭不禁用独立的出口压制", action.is_active() and not ai.tactics.area_suppression.is_active())
	await _prepare_visible()
	action.cover_inference_distance = 0.01
	await _hide()
	_check("最后目击离掩体太远时回退普通压制", not action.is_active() and ai.tactics.area_suppression.is_active())
	# 中心在射程内，但部分出口太远：不会启动射不到的高级动作。
	await _prepare_visible()
	enemy.global_position = Vector3(24.5, 0, -4)
	enemy.look_at(SEEN_POSITION)
	var original_range: float = enemy.weapon.fire_range
	enemy.weapon.fire_range = enemy.get_shot_origin().distance_to(ai.last_seen_position + Vector3.UP * 0.8) + 0.01
	await _hide()
	_check("只有一端在射程内时回退普通压制", not action.is_active() and ai.tactics.area_suppression.is_active())
	_check("射程用例确实只有一端有合格候选", not action.first_exit.is_empty() and action.second_exit.is_empty())
	enemy.weapon.fire_range = original_range
	await _prepare_visible()
	var obstruction := StaticBody3D.new()
	var obstruction_shape := CollisionShape3D.new()
	var obstruction_box := BoxShape3D.new()
	obstruction_box.size = Vector3(0.2, 3, 10)
	obstruction_shape.shape = obstruction_box
	obstruction.add_child(obstruction_shape)
	scene.add_child(obstruction)
	obstruction.global_position = Vector3(24, 1.5, -2)
	await _hide()
	_check("出口被其他墙体遮挡时回退普通压制", not action.is_active() and ai.tactics.area_suppression.is_active())
	obstruction.queue_free()
	await physics_frame
	await physics_frame
	await _prepare_visible()
	var regions := get_nodes_in_group("cover_region")
	for region in regions:
		region.remove_from_group("cover_region")
	await _hide()
	_check("没有已知掩体时回退普通压制", not action.is_active() and ai.tactics.area_suppression.is_active())
	for region in regions:
		region.add_to_group("cover_region")
	await _prepare_visible()
	await _hide()
	player.global_position = SEEN_POSITION
	for frame in range(3):
		await physics_frame
	ai._physics_process(1.0 / 60.0)
	_check("出口压制重新目击后恢复交战", ai.was_seeing_player and not action.is_active())
	await _hide()
	action.remaining = 0.01
	ai._physics_process(0.02)
	_check("出口压制到时交给追踪搜索", not action.is_active() and ai.state in [ai.State.TRACK, ai.State.SEARCH, ai.State.INVESTIGATE])
	await _prepare_visible()
	await _hide()
	cover.queue_free()
	await physics_frame
	await physics_frame
	ai._physics_process(0.02)
	_check("所属掩体移除后安全结束出口压制", not action.is_active())
	ai.reset_actions()
	_check("刷新统一清理两种压制并恢复默认接口", not action.is_active() and not ai.tactics.area_suppression.is_active() and ai.tactics.suppression == ai.tactics.area_suppression)
	_finish()


func _prepare_visible() -> void:
	ai.reset_actions()
	ai.search.reset()
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", true)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", true)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"attack_position", false)
	ai.tactics.fire_reaction_seconds = 0.0
	ai.tactics.burst_pause_seconds = 0.2
	action.cover_inference_distance = 1.75
	ai.attack_position_uncertainty = 0.0
	ai.combat_type = ai.CombatType.RANGED
	ai.has_visual_memory = false
	ai.was_seeing_player = false
	ai.last_seen_direction = Vector3.ZERO
	ai.search.debug_tracking_cheat = false
	ai.search.lost_target_hint_chance = 0.0
	ai.search.search_hint_chance = 0.0
	ai.state = ai.State.IDLE
	enemy.global_position = ENEMY_POSITION
	enemy.velocity = Vector3.ZERO
	enemy.shooting_enabled = true
	enemy.clear_aim()
	enemy.shot_cooldown = 0.0
	player.global_position = SEEN_POSITION
	enemy.look_at(SEEN_POSITION)
	for frame in range(4):
		await physics_frame
	ai._physics_process(1.0 / 60.0)


func _hide() -> void:
	player.global_position = HIDDEN_POSITION
	for frame in range(3):
		await physics_frame
	ai._physics_process(1.0 / 60.0)


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	print("出口压制：", checks.size(), " 项")
	scene.free()
	quit(0 if checks.values().all(func(value): return value) else 1)
