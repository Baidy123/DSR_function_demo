extends SceneTree

var checks := 0
var failures := 0

# 保留感知和物理执行，只冻结选案，单独观察失视事件是否生成错误机会。
class KeepOption extends "res://enemy_action_selector.gd":
	var observed_pending := false
	func assess_options(ai: Node, _sees: bool) -> Array[Dictionary]:
		observed_pending = ai.utility_suppression_pending
		var options: Array[Dictionary] = []
		if not ai.utility_current.is_empty(): options.append(ai.utility_current)
		return options

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
	ai.cover_selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	ai.search.tracking_cheat_enabled = false
	for id in ["suppression", "exit_suppression"]:
		var resource = load("res://enemy_actions/" + id + ".tres")
		ai.unit_type.available_actions.append(resource)
		ai.training.allowed_actions.append(resource)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", true)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", true)
	player.global_position = Vector3(18.585854, 0.001, 4.430427)
	enemy.global_position = Vector3(24.327566, 0.001, 7.430623)
	enemy.look_at(player.global_position)
	for f in range(5): await physics_frame
	check(ai.perception.can_see_player(), "测试起点真实目击玩家")
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	var evaluator = ai.action_selector
	for f in range(60):
		await physics_frame
		evaluator.advance_evaluation(ai, true)
	var covers: Array = evaluator.assess_options(ai, true).filter(func(o): return o.id == &"cover")
	check(not covers.is_empty(), "真实地图可选躲藏目标")
	if covers.is_empty():
		quit(1)
		return
	var cover_choice: Dictionary = covers[0]
	var suppressed := [&"suppression", &"exit_suppression"]
	ai.utility_suppression_pending = true
	ai._start_utility_option(cover_choice, true)
	check(not ai.utility_suppression_pending, "选择主动躲藏清除旧压制机会")
	# 真正走入掩体会失视；固定在同一目的地单独检查这一帧的触发规则。
	enemy.global_position = cover_choice.destination.hide
	ai.cover.phase = ai.cover.Phase.HIDE
	ai.was_seeing_player = true
	ai.utility_suppression_pending = false
	ai.action_selector = KeepOption.new()
	for f in range(3): await physics_frame
	check(not ai.perception.can_see_player(), "敌人退到掩体后确实丢失视野")
	ai._physics_process(1.0 / 60.0)
	check(not ai.utility_suppression_pending, "主动躲藏失视不生成压制机会")
	ai.start_suppression()
	check(not ai.utility_suppression_pending, "躲藏中额外压制请求也不会遗留机会")
	ai.cover.reset()
	ai.was_seeing_player = true
	ai.invalidate_utility()
	ai._physics_process(1.0 / 60.0)
	check(not ai.action_selector.observed_pending, "掩体动作刚结束、下一帧失视也不补发压制")
	# 即使有旧标记，掩体执行期间也不能把压制送入候选池抢占。
	ai.utility_suppression_pending = true
	enemy.global_position = Vector3(24.327566, 0.001, 7.430623)
	for f in range(3): await physics_frame
	check(ai.actions[&"suppression"].utility_available(), "仍有可射区域时单独验证主动躲藏的资格门槛")
	var options: Array = evaluator.assess_options(ai, false)
	check(not options.any(func(o): return o.id in suppressed), "掩体动作不被普通或出口压制抢占")
	enemy.global_position = cover_choice.destination.hide
	for f in range(3): await physics_frame
	ai.utility_suppression_pending = false
	ai.cover.reset()
	ai.utility_current = {"id": &"search", "destination": {}, "cost": 0.0}
	ai.state = ai.State.SEARCH
	ai.was_seeing_player = false
	ai._physics_process(1.0 / 60.0)
	check(not ai.utility_suppression_pending, "躲藏结束后持续失视不延迟补发压制")
	# 两种去掩体换弹都代表主动撤离视线，不能残留旧机会。
	ai.action_selector = evaluator
	for plan in [&"after_cover", &"on_way"]:
		ai.reset_actions()
		ai.is_alerted = true
		enemy.cancel_reload()
		enemy.ammo.magazine_rounds = 0
		ai.utility_suppression_pending = true
		ai._start_utility_option({"id": &"reload", "plan": plan, "destination": cover_choice.destination, "cost": 0.0}, false)
		check(ai.reload_plan == plan and not ai.utility_suppression_pending, "去掩体换弹清除旧压制机会：" + String(plan))
	# 正常交战丢失目标仍保留压制机会（是否真的压制另由射界和评分决定）。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 12
	ai.action_selector = KeepOption.new()
	ai.utility_current = {"id": &"engage", "destination": {}, "cost": 0.0}
	ai.was_seeing_player = true
	ai._physics_process(1.0 / 60.0)
	check(ai.utility_suppression_pending, "正常交战失视仍可考虑压制")
	print("UTILITY SUPPRESSION TRIGGER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
