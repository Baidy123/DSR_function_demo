extends SceneTree

var checks := 0
var failed := 0

class FixedOptions extends "res://scripts/enemy/enemy_action_selector.gd":
	var choices: Array[Dictionary] = []
	func assess_options(_ai: Node, _sees_player: bool) -> Array[Dictionary]:
		return choices

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	scene.get_node("Player").set_physics_process(false)
	ai.set_physics_process(false)
	check(ai.has_method("_update_utility_decision"), "AI使用统一Utility决策入口")
	check(ai.get("utility_options") != null, "所有战术候选提供共同分数明细")
	if failed > 0:
		finish()
		return
	var player = scene.get_node("Player")
	var arena = scene.get_node("Arena")
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	player.get_node("Health").debug_invincible = true
	ai.cover_selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	enemy.look_at(player.global_position)
	for frame in range(5): await physics_frame
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	var evaluator = ai.action_selector
	for frame in range(60):
		await physics_frame
		evaluator.advance_evaluation(ai, true)
	var options: Array = evaluator.assess_options(ai, true)
	check(options.any(func(o): return o.id == &"engage") and options.any(func(o): return o.id == &"cover"), "有弹时交战与躲藏共同参选")
	check(not options.any(func(o): return o.id == &"reload"), "不擅自新增半匣提前换弹")
	enemy.ammo.magazine_rounds = 0
	options = evaluator.assess_options(ai, true)
	check(options.any(func(o): return o.id == &"reload") and options.any(func(o): return o.id == &"cover") and options.any(func(o): return o.id == &"engage"), "空匣不会将其他战术候选排除在比较之外")
	check(options.all(func(o): return o.has("breakdown") and is_equal_approx(o.cost, o.breakdown.fire_cost + o.breakdown.risk_cost + o.breakdown.information_cost)), "换弹和普通动作都使用相同分项及总分")
	var covers: Array = options.filter(func(o): return o.id == &"cover")
	check(not covers.is_empty(), "真实地图提供可达掩体用于统一调度检查")
	if covers.is_empty():
		finish()
		return
	var cover_choice: Dictionary = covers[0].duplicate(true)
	cover_choice.cost = 0.0
	var reload_choice := {"id": &"reload", "plan": &"here", "destination": {}, "cost": 5.0}
	var engage_choice := {"id": &"engage", "destination": {}, "cost": 10.0}
	var fixed := FixedOptions.new()
	fixed.choices = [cover_choice, reload_choice, engage_choice]
	ai.action_selector = fixed
	ai._physics_process(0.01)
	check(ai.utility_current.get("id") == &"cover" and ai.cover.is_active() and ai.reload_plan.is_empty() and not enemy.ammo.is_reloading, "调度按共同分数选择躲藏，空匣不抢先换弹")
	var original: Vector3 = ai.cover.hide_position
	reload_choice.cost = -2.0
	ai.invalidate_utility()
	ai._update_utility_decision(0.1, true)
	check(ai.utility_current.id == &"cover" and ai.cover.hide_position == original, "统一保持期适用于换弹与躲藏之间切换")
	reload_choice.cost = -0.1
	ai.invalidate_utility()
	ai._update_utility_decision(0.6, true)
	check(ai.utility_current.id == &"cover", "保持期结束仍拒绝微小分差切换")
	reload_choice.cost = -2.0
	ai.invalidate_utility()
	ai._update_utility_decision(0.4, true)
	check(ai.utility_current.id == &"reload" and enemy.ammo.is_reloading and not ai.cover.is_active(), "显著更好的换弹方案通过同一选择入口接管")
	enemy.update_weapon(0.3)
	var progress: float = enemy.ammo.reload_progress
	engage_choice.cost = -5.0
	ai.invalidate_utility()
	ai._update_utility_decision(0.7, true)
	check(ai.utility_current.id == &"engage" and ai.reload_plan.is_empty() and enemy.ammo.is_reloading and enemy.ammo.reload_progress == progress, "换弹中改选交战保留基础换弹进度，不被计划独占")
	check(not enemy.can_fire(), "统一切换不能绕过换弹禁射")
	# 撤销动作权限不能被保持时间困住。
	ai.action_selector = evaluator
	ai.training.allowed_actions = ai.training.allowed_actions.filter(func(a): return a.action_id != &"engage")
	ai._physics_process(0.01)
	check(ai.utility_current.get("id") != &"engage", "权限撤销立即淘汰当前动作")
	# 无声隐藏位置变化不改变评估。
	ai.last_known_position = arena.to_global(Vector3(0, 0, 2.5))
	ai.last_seen_position = ai.last_known_position
	options = evaluator.assess_options(ai, false)
	player.global_position += Vector3(1, 0, -1)
	check(options == evaluator.assess_options(ai, false), "统一评估不读取被隐藏玩家的新位置")
	# 实际躲藏受击保留原即时中断；后续同枪来弹只增加压力，不重新抢占。
	ai.reset_actions()
	enemy.cancel_reload()
	ai._start_utility_option(cover_choice, false)
	ai.cover.phase = ai.cover.Phase.HIDE
	enemy.receive_hit(1.0, player.global_position)
	check(not ai.cover.is_active(), "动作保持不会阻止HIDE受伤中断")
	ai.notice_shot(player.global_position + Vector3.UP * 0.8, enemy.get_shot_origin())
	check(not ai.cover.is_active(), "同一枪来弹不能绕过Utility再次躲藏")
	player.is_in_dialogue = true
	ai._physics_process(0.1)
	check(ai.utility_current.is_empty() and not enemy.ammo.is_reloading, "对话清理统一决策和换弹执行")
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("UTILITY AI: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
