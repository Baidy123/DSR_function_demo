extends SceneTree

var checks := {}
var scene: Node
var enemy
var ai
var tactics
var action
var player
const TARGET := Vector3(19.92596, 0, -4.2821)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	enemy = scene.get_node("Arena/Enemy")
	ai = enemy.get_node("AI")
	tactics = ai.tactics
	player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	enemy.shooting_enabled = false
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	action = tactics.attack_position
	_check("Tactics包含独立攻击位置动作", action != null)
	if action == null:
		_finish()
		return
	player.get_node("Health").debug_invincible = true
	player.global_position = TARGET
	for frame in range(60):
		await physics_frame
		if ai.is_arena_active() and not ai.cover_selection._path_to(enemy.global_position, enemy.global_position).is_empty():
			break
	_prepare()
	tactics.attack_position_chance = 0.0
	ai._physics_process(1.0 / 60.0)
	_check("概率0不启动", not action.is_active())
	tactics.attack_position_chance = 1.0
	for frame in range(5):
		ai._physics_process(1.0 / 60.0)
	_check("持续可见不重新抽概率", not action.is_active())
	ai.was_seeing_player = false
	ai._physics_process(1.0 / 60.0)
	_check("重新目击且概率1开始查找", action.is_active())
	await _finish_finding()
	_check("选择可用攻击位置", action.phase == action.Phase.MOVE or action.phase == action.Phase.HOLD)
	if not action.is_active():
		_finish()
		return
	var destination: Vector3 = action.destination
	var wall = action.active_cover
	var known := TARGET + Vector3.UP * 0.8
	_check("目的地通过真实空间射界遮身检查", ai.cover_selection.assess_attack_point(destination, wall, known, known).usable)
	var selected_length: float = ai.cover_selection._path_length(enemy.global_position, destination)
	var nearest := true
	for result in ai.cover_selection.get_attack_assessments(known, known):
		if result.usable and result.position.distance_to(TARGET) <= ai.perception.sight_distance and ai.cover_selection._path_length(enemy.global_position, result.position) < selected_length - 0.01:
			nearest = false
	_check("合格位置按实际路径较短选择", nearest)
	_check("攻击目的地位于感知距离内", destination.distance_to(TARGET) <= ai.perception.sight_distance)
	# 直接改变隐藏玩家坐标，动作只能继续使用已有目击记忆。
	player.global_position = Vector3(29, 0, 8)
	var before: Vector3 = ai.last_seen_position
	for frame in range(3):
		await physics_frame
	_check("失视测试确实没有看见玩家", not ai.perception.can_see_player())
	ai._physics_process(1.0 / 60.0)
	var direction: Vector3 = action.step(1.0 / 60.0, false)
	_check("途中失视继续前往同一目的地", action.is_active() and action.destination == destination and not direction.is_zero_approx())
	_check("主AI失视时没有提前切入搜索", ai.state == ai.State.REPOSITION)
	_check("隐藏玩家新坐标不改变依据", ai.last_seen_position == before and action.destination == destination)
	enemy.global_position = destination
	action.step(1.0 / 60.0, false)
	_check("到位仍未见玩家交给追踪搜索", not action.is_active() and ai.state in [ai.State.TRACK, ai.State.SEARCH, ai.State.INVESTIGATE])
	player.global_position = TARGET
	await physics_frame
	_prepare()
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"attack_position", false)
	ai._physics_process(1.0 / 60.0)
	_check("无能力时概率1也不启动", not action.is_active())
	_prepare()
	ai.combat_type = ai.CombatType.MELEE
	ai._physics_process(1.0 / 60.0)
	_check("近战不使用远程攻击位置", not action.is_active())
	_prepare()
	var weapon = enemy.weapon
	enemy.weapon = null
	ai._physics_process(1.0 / 60.0)
	_check("无枪不启动", not action.is_active())
	enemy.weapon = weapon
	_prepare()
	enemy.weapon = weapon.duplicate()
	enemy.weapon.fire_range = 0.01
	ai._physics_process(1.0 / 60.0)
	await _finish_finding()
	_check("没有合格位置退出且不无限重试", not action.is_active())
	for frame in range(5):
		ai._physics_process(1.0 / 60.0)
	_check("本次失败后持续目击不重抽", not action.is_active())
	enemy.weapon = weapon
	_prepare()
	ai._physics_process(1.0 / 60.0)
	await _finish_finding()
	destination = action.destination
	enemy.global_position = destination
	enemy.look_at(TARGET)
	action.step(1.0 / 60.0, true)
	_check("实际到位且合格后进入占位", action.phase == action.Phase.HOLD and ai.state == ai.State.HOLD_POSITION)
	var stopped: Vector3 = action.step(0.1, true)
	_check("占位期间保持不动", stopped.is_zero_approx() and action.is_active())
	tactics.try_attack_position()
	_check("正在占位时重新目击不重启查找", action.phase == action.Phase.HOLD and action.destination == destination)
	ai.last_seen_position = destination + (destination - TARGET).normalized() * 5.0
	action.step(0.3, true)
	_check("玩家绕侧导致位置失效则回普通交战", not action.is_active() and ai.state == ai.State.REPOSITION)
	_prepare()
	ai._physics_process(1.0 / 60.0)
	tactics.cover.take_cover_chance = 1.0
	tactics.cover.notice_shot(TARGET + Vector3.UP * 0.8, enemy.get_shot_origin())
	_check("来弹成功躲藏时让出攻击占位", tactics.cover.is_active() and not action.is_active())
	tactics.try_attack_position()
	_check("躲藏期间攻击占位不会抢回控制", tactics.cover.is_active() and not action.is_active())
	_prepare()
	ai._physics_process(1.0 / 60.0)
	tactics.cover.take_cover_chance = 0.0
	tactics.cover.notice_shot(TARGET + Vector3.UP * 0.8, enemy.get_shot_origin())
	_check("来弹未触发躲藏时保留攻击行动", not tactics.cover.is_active() and action.is_active())
	await _finish_finding()
	action.step(100.0, true)
	_check("转移超时退出而不是永久卡住", not action.is_active())
	_prepare()
	ai._physics_process(1.0 / 60.0)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"attack_position", false)
	action.step(0.1, true)
	_check("运行中关闭能力会取消行动", not action.is_active())
	_prepare()
	ai._physics_process(1.0 / 60.0)
	enemy.receive_hit(enemy.health)
	_check("死亡立即清理动作", not action.is_active())
	enemy.reset_target()
	_check("刷新清理动作并重置目击边沿", not action.is_active() and not ai.was_seeing_player)
	await _walk_and_fire()
	_finish()


func _prepare() -> void:
	ai.reset_actions()
	ai.combat_type = ai.CombatType.RANGED
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"attack_position", true)
	tactics.attack_position_chance = 1.0
	enemy.global_position = Vector3(24, 0, -2)
	enemy.velocity = Vector3.ZERO
	enemy.look_at(TARGET)
	ai.was_seeing_player = false
	ai.state = ai.State.IDLE
	ai.is_alerted = false
	# 此处验证成功躲藏抢占，不让受击位置的随机误差改变可用掩体。
	ai.attack_position_uncertainty = 0.0
	ai.search.debug_tracking_cheat = false
	ai.search.lost_target_hint_chance = 0.0


func _finish_finding() -> void:
	for frame in range(200):
		if action.phase != action.Phase.FIND:
			break
		action.step(1.0 / 60.0, true)
		await physics_frame


func _walk_and_fire() -> void:
	player.global_position = TARGET
	await physics_frame
	_prepare()
	enemy.shooting_enabled = true
	ai.cover_selection.debug_cover_selection = true
	tactics.fire_reaction_seconds = 0.0
	var reached := false
	var frames := 0
	for frame in range(1200):
		await physics_frame
		var previous_phase = action.phase
		var previous_position: Vector3 = enemy.global_position
		var previous_remaining: float = action._remaining
		var previous_stuck: float = action._stuck
		ai._physics_process(1.0 / 60.0)
		if previous_phase != action.phase:
			print("动作变化 ", previous_phase, " -> ", action.phase, " pos=", previous_position, " timer=", previous_remaining, " stuck=", previous_stuck)
		frames += 1
		if action.phase == action.Phase.HOLD:
			reached = true
			break
		if frame > 200 and not action.is_active():
			break
	_check("真实导航移动到合格墙角", reached)
	var shots: int = enemy.shot_count
	for frame in range(180):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	_check("占位后使用原射击流程开火", reached and enemy.shot_count > shots)
	print("实走帧=", frames, " 位置=", enemy.global_position, " 目标=", action.destination)
	player.global_position = Vector3(-20, 0, 30)
	for frame in range(4):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	_check("离场不保留攻击动作", not action.is_active())


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	print("攻击占位：", checks.size(), " 项")
	scene.free()
	quit(0 if checks.values().all(func(value): return value) else 1)
