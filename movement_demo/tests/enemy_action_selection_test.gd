extends SceneTree

var checks := 0
var failures := 0

class CountingAttack extends "res://enemy_attack_position_action.gd":
	var calls := 0
	func step(_delta: float, _sees_player: bool) -> Vector3:
		calls += 1
		return Vector3.RIGHT

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
	check(ai.get("action_selector") != null and ai.has_method("step_selected_action"), "AI持有选择器并提供统一动作更新入口")
	if failures > 0:
		finish()
		return
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	player.global_position = enemy.global_position + Vector3(0, 0, 2)
	for frame in range(6):
		await physics_frame
	var selector = ai.action_selector
	check(selector is RefCounted and ai.get_child_count() == 2, "选择器是普通对象且不增加场景节点")
	ai.reset_actions()
	for entry in [[ai.State.IDLE, &""], [ai.State.PATROL, &"patrol"], [ai.State.TRACK, &"search"], [ai.State.SEARCH, &"search"], [ai.State.INVESTIGATE, &"search"], [ai.State.APPROACH, &"engage"], [ai.State.REPOSITION, &"engage"], [ai.State.HOLD_POSITION, &"engage"]]:
		ai.state = entry[0]
		check(selector.select_action(ai) == entry[1], "保留主状态对应动作 " + str(entry[0]))
	var attack = ai.actions[&"attack_position"]
	var suppression = ai.actions[&"suppression"]
	var exits = ai.actions[&"exit_suppression"]
	attack.phase = attack.Phase.FIND
	check(selector.select_action(ai) == &"attack_position", "架枪活动时优先于普通接敌")
	suppression.active = true
	ai.current_suppression = suppression
	check(selector.select_action(ai) == &"suppression", "当前压制优先于架枪")
	ai.cover.phase = ai.cover.Phase.HIDE
	check(selector.select_action(ai) == &"cover", "活动躲藏优先接管")
	ai.on_tactical_action_started(&"cover")
	check(not attack.is_active() and not suppression.is_active(), "躲藏接管由AI取消架枪与当前压制")
	ai.cover.reset()
	exits.active = true
	ai.current_suppression = exits
	check(selector.select_action(ai) == &"exit_suppression", "调度当前出口压制而非普通压制")
	attack.phase = attack.Phase.FIND
	ai.on_tactical_action_started(&"exit_suppression")
	check(not attack.is_active() and exits.is_active(), "压制接管只取消被抢占的架枪")
	ai.reset_actions()
	ai.state = ai.State.HOLD_POSITION
	var replacement := CountingAttack.new()
	replacement.setup(ai)
	replacement.phase = replacement.Phase.FIND
	ai.actions[&"attack_position"] = replacement
	var previous_target: Vector3 = enemy.agent.target_position
	var previous_memory: Vector3 = ai.last_known_position
	selector.select_action(ai)
	check(replacement.calls == 0 and enemy.agent.target_position == previous_target and ai.last_known_position == previous_memory, "选择查询不执行动作也不修改导航或记忆")
	check(ai.step_selected_action(0.1, false) == Vector3.RIGHT and replacement.calls == 1, "统一入口恰好调用一次兵种提供的动作实现")
	ai.actions[&"attack_position"] = attack
	var remembered: Vector3 = enemy.global_position + Vector3.RIGHT * 2.0
	for action in [ai.cover, suppression, exits]:
		ai.state = ai.State.HOLD_POSITION
		ai.tactics.ranged_has_destination = true
		ai.tactics.ranged_repath_timer = 3.0
		ai.last_known_position = remembered
		if action == ai.cover:
			action.look_position = remembered
			action.phase = action.Phase.HIDE
			action._finish(true)
		else:
			action.active = true
			action.finish(true)
		check(not action.is_active() and ai.state == ai.State.REPOSITION and not ai.tactics.ranged_has_destination and ai.tactics.ranged_repath_timer == 0.0 and enemy.agent.target_position == enemy.global_position, "结束信号统一回到交战 " + str(action.action_id))
	ai.is_alerted = true
	ai.last_known_position = remembered
	ai.has_visual_memory = true
	ai.last_seen_position = remembered
	ai.cover.look_position = remembered
	ai.cover.phase = ai.cover.Phase.HIDE
	ai.cover._finish(false)
	check(ai.last_known_position == remembered and ai.state in [ai.State.TRACK, ai.State.SEARCH], "失视结束沿用动作记忆进入追踪搜索")
	ai.cover.phase = ai.cover.Phase.HIDE
	ai.cover.on_damage_received()
	check(not ai.cover.is_active() and ai.state == ai.State.REPOSITION and enemy.agent.target_position == ai.last_known_position, "躲藏受击退出仍由AI恢复已知位置接敌")
	for id in [&"cover", &"suppression", &"exit_suppression"]:
		ai.state = ai.State.PATROL
		enemy.agent.target_position = remembered
		ai.cancel_action(id)
		check(ai.state == ai.State.PATROL and enemy.agent.target_position == remembered, "取消不会触发结束衔接覆盖接管方 " + str(id))
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("AI ACTION SELECTION: ", checks - failures, "/", checks)
	quit(0 if failures == 0 else 1)
