extends SceneTree

# 检查动作接口与决策分工，不依赖随机挑中某个墙角。
var checks: Array[bool] = []
var outcomes: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var tactics = ai.tactics
	var action = tactics.attack_position
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	enemy.shooting_enabled = false
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	player.global_position = Vector3(19.92596, 0, -4.2821)
	for frame in range(60):
		await physics_frame
		if ai.is_arena_active():
			break
	var has_interface: bool = action.has_method("can_start") and action.has_method("start") and action.has_signal("finished") and action.has_signal("phase_changed")
	_check("提供条件、启动和结果接口", has_interface)
	if not has_interface:
		scene.free()
		quit(1)
		return
	ai.reset_actions()
	ai.combat_type = ai.CombatType.RANGED
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"attack_position", true)
	tactics.attack_position_chance = 0.0
	ai.has_visual_memory = true
	ai.last_seen_position = player.global_position
	var old_target: Vector3 = enemy.agent.target_position
	seed(1234)
	var expected_random := randf()
	seed(1234)
	_check("条件查询不受决策概率影响", action.can_start())
	_check("条件查询不消耗随机数", randf() == expected_random)
	_check("条件查询不启动或改变导航", not action.is_active() and enemy.agent.target_position == old_target)
	tactics.try_attack_position()
	_check("概率0由决策层拒绝启动", not action.is_active())
	tactics.attack_position_chance = 1.0
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"attack_position", false)
	_check("关闭权限连直接启动也被拒绝", not action.start(player.global_position, false))
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"attack_position", true)
	action.finished.connect(func(sees_player: bool, known_position: Vector3, reason: String):
		outcomes.append({"visible": sees_player, "known": known_position, "reason": reason, "active": action.is_active()}))
	var snapshot: Vector3 = player.global_position
	_check("直接启动接收已知位置", action.start(snapshot, true))
	_check("启动通过阶段通知进入选位", ai.state == ai.State.REPOSITION)
	_check("运行中拒绝重复启动", not action.start(snapshot + Vector3.RIGHT, true) and action._query_target == snapshot + Vector3.UP * 0.8)
	# 抢占方已经设定了自己的导航目标，清理旧动作不能覆盖它。
	enemy.agent.target_position = snapshot + Vector3.LEFT
	old_target = enemy.agent.target_position
	action.reset()
	_check("取消清理进度但不覆盖接管方导航", not action.is_active() and enemy.agent.target_position == old_target)
	_check("取消不触发重新决策", outcomes.is_empty())
	# 极短射程保证找不到合格点，验证失败反馈与原追踪分支。
	enemy.weapon = enemy.weapon.duplicate()
	enemy.weapon.fire_range = 0.001
	action.start(snapshot, true)
	for frame in range(200):
		if not action.is_active():
			break
		action.step(1.0 / 60.0, false)
		await physics_frame
	_check("失败仅反馈一次且先清理动作", outcomes.size() == 1 and not outcomes[0].active)
	_check("反馈保留受击快照及结束原因", outcomes.size() == 1 and outcomes[0].known == snapshot and not outcomes[0].visible and not outcomes[0].reason.is_empty())
	_check("决策层收到反馈后恢复追踪搜索", ai.state in [ai.State.TRACK, ai.State.SEARCH, ai.State.INVESTIGATE] and ai.last_known_position == snapshot)
	action.step(0.1, false)
	_check("结束后更新不重复反馈", outcomes.size() == 1)
	print("动作接口：", checks.size(), " 项")
	scene.free()
	quit(0 if checks.all(func(passed): return passed) else 1)


func _check(label: String, passed: bool) -> void:
	checks.append(passed)
	print("PASS " if passed else "FAIL ", label)
