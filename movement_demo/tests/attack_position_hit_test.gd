extends SceneTree

var scene: Node
var enemy
var ai
var action
var player
var checks := {}
const TARGET := Vector3(19.92596, 0, -4.2821)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	enemy = scene.get_node("Arena/Enemy")
	ai = enemy.get_node("AI")
	action = ai.tactics.attack_position
	player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	enemy.shooting_enabled = false
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	player.global_position = TARGET
	for frame in range(60):
		await physics_frame
		if ai.is_arena_active() and not ai.cover_selection._path_to(enemy.global_position, enemy.global_position).is_empty():
			break
	_prepare()
	ai.tactics.attack_position_chance = 0.0
	enemy.receive_hit(1.0, TARGET)
	_check("中弹概率0不启动", not action.is_active())
	ai.tactics.attack_position_chance = 1.0
	enemy.receive_hit(1.0, TARGET)
	_check("未曾目击时中弹概率1也启动", action.phase == action.Phase.FIND)
	_check("受击选位不伪造目击记忆", not ai.has_visual_memory and ai.last_seen_position == Vector3.ZERO)
	_check("选位使用受击估计位置", action.is_active() and action._query_target.is_equal_approx(ai.last_known_position + Vector3.UP * 0.8))
	if not action.is_active():
		_finish()
		return
	var snapshot: Vector3 = action._query_target
	player.global_position = Vector3(29, 0, 8)
	for frame in range(200):
		if action.phase != action.Phase.FIND:
			break
		action.step(1.0 / 60.0, false)
		await physics_frame
	_check("中弹选位能找到实际可用墙角", action.phase == action.Phase.MOVE)
	_check("隐藏玩家移动不更新受击选位依据", action._query_target == snapshot and not ai.has_visual_memory)
	var destination: Vector3 = action.destination
	enemy.receive_hit(1.0, TARGET + Vector3.RIGHT)
	_check("连续中弹不重启已有转移", action.phase == action.Phase.MOVE and action.destination == destination)
	_check("已有行动不被新受击位置强制改目标", action._query_target == snapshot)
	# 没有新目击，到点继续交给原追踪／搜索，并保留受击位置而非空目击。
	enemy.global_position = destination
	action.step(0.1, false)
	_check("到点仍未见玩家不盲目架枪", not action.is_active())
	_check("失视结束保留本次受击威胁位置", ai.last_known_position.is_equal_approx(snapshot - Vector3.UP * 0.8))
	_prepare()
	ai.cover.take_cover_chance = 0.0
	ai.cover.notice_shot(TARGET + Vector3.UP * 0.8, enemy.get_shot_origin())
	_check("只有附近来弹不触发中弹攻击选位", not action.is_active())
	_prepare()
	enemy.receive_hit(0.0, TARGET)
	enemy.receive_hit(-1.0, TARGET)
	_check("无有效伤害不启动", not action.is_active())
	enemy.receive_hit(1.0)
	_check("没有攻击者位置不凭空选位", not action.is_active())
	_prepare()
	ai.tactics.can_use_attack_positions = false
	enemy.receive_hit(1.0, TARGET)
	_check("能力关闭时中弹不启动", not action.is_active())
	_prepare()
	ai.combat_type = ai.CombatType.MELEE
	enemy.receive_hit(1.0, TARGET)
	_check("近战中弹不使用远程选位", not action.is_active())
	_prepare()
	var weapon = enemy.weapon
	enemy.weapon = null
	enemy.receive_hit(1.0, TARGET)
	_check("无武器中弹不启动", not action.is_active())
	enemy.weapon = weapon
	_prepare()
	ai.cover.phase = ai.cover.Phase.WATCH
	enemy.receive_hit(1.0, TARGET)
	_check("现有掩体动作优先", ai.cover.is_active() and not action.is_active())
	_prepare()
	ai.cover.phase = ai.cover.Phase.HIDE
	enemy.receive_hit(1.0, TARGET)
	_check("躲藏中受伤退出后可以尝试攻击选位", not ai.cover.is_active() and action.is_active())
	ai.cover.take_cover_chance = 1.0
	ai.cover.notice_shot(TARGET + Vector3.UP * 0.8, enemy.get_shot_origin())
	_check("躲藏受伤后同枪来弹不抢回躲藏", not ai.cover.is_active() and action.is_active())
	_prepare()
	ai.attack_position_uncertainty = 1.0
	enemy.receive_hit(1.0, TARGET)
	_check("受击位置保留原有估计误差", action._query_target.is_equal_approx(ai.last_known_position + Vector3.UP * 0.8) and not ai.last_known_position.is_equal_approx(TARGET))
	# 实际主AI取得新目击，后续检查应使用新目击位置。
	player.global_position = TARGET
	enemy.look_at(TARGET)
	for frame in range(3):
		await physics_frame
	ai._physics_process(1.0 / 60.0)
	_check("真正看见后更新目击记忆且不重启查找", ai.has_visual_memory and ai.last_seen_position.is_equal_approx(TARGET) and action.is_active())
	_check("取得视线后选位改用真实目击", not action._using_hit_memory and action._known_position().is_equal_approx(TARGET))
	await _walk_after_hit()
	# 从原攻击动作处退场，原清理逻辑仍有效。
	player.global_position = Vector3(-20, 0, 30)
	for frame in range(4):
		await physics_frame
	_prepare()
	enemy.receive_hit(1.0, TARGET)
	_check("竞技场外中弹不启动", not action.is_active())
	enemy.receive_hit(enemy.health, TARGET)
	_check("致命伤不启动选位", enemy.is_dead and not action.is_active())
	_finish()


func _prepare() -> void:
	ai.reset_actions()
	ai.combat_type = ai.CombatType.RANGED
	ai.tactics.can_use_attack_positions = true
	ai.tactics.attack_position_chance = 1.0
	ai.attack_position_uncertainty = 0.0
	ai.has_visual_memory = false
	ai.last_seen_position = Vector3.ZERO
	ai.last_seen_direction = Vector3.ZERO
	ai.was_seeing_player = false
	ai.is_alerted = false
	ai.state = ai.State.IDLE
	ai.search.debug_tracking_cheat = false
	ai.search.lost_target_hint_chance = 0.0
	ai.search.search_hint_chance = 0.0
	enemy.global_position = Vector3(24, 0, -2)
	enemy.velocity = Vector3.ZERO


func _walk_after_hit() -> void:
	_prepare()
	player.global_position = TARGET
	player.get_node("Health").debug_invincible = true
	enemy.look_at(TARGET)
	ai.tactics.attack_position_chance = 0.0
	ai.tactics.fire_reaction_seconds = 0.0
	await physics_frame
	ai._physics_process(1.0 / 60.0)
	_check("实走前持续目击尚未触发选位", ai.was_seeing_player and not action.is_active())
	ai.tactics.attack_position_chance = 1.0
	enemy.receive_hit(1.0, TARGET)
	_check("实走由真正扣血触发选位", action.phase == action.Phase.FIND)
	enemy.shooting_enabled = true
	var reached := false
	for frame in range(1200):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if action.phase == action.Phase.HOLD:
			reached = true
			break
		if frame > 200 and not action.is_active():
			break
	_check("中弹后真实导航到达墙角架枪", reached)
	var shots: int = enemy.shot_count
	for frame in range(180):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	_check("中弹触发的墙角架枪实际开火", reached and enemy.shot_count > shots)
	enemy.shooting_enabled = false


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	print("中弹攻击选位：", checks.size(), " 项")
	scene.free()
	quit(0 if checks.values().all(func(value): return value) else 1)
