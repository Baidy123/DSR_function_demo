extends SceneTree

class Body extends Node3D:
	var move_speed: float = 1.0

class Context extends Node:
	var utility_horizon_seconds: float = 4.0
	var utility_fire_weight: float = 3.0
	var utility_information_weight: float = 1.0
	var risk: float = 3.0
	var actor: Body
	func _reload_risk_aversion() -> float:
		return risk
	func _horizontal_distance_between(a: Vector3, b: Vector3) -> float:
		return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	func _reload_exposure(_point: Vector3, _threat: Vector3) -> float:
		return 1.0

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var selector = load("res://enemy_action_selector.gd").new()
	check(selector.has_method("score_outcome"), "统一行动评分入口存在")
	if failures > 0:
		quit(1)
		return
	var ai := Context.new()
	var engage: Dictionary = selector.score_outcome(ai, 0.0, 4.0)
	var cover: Dictionary = selector.score_outcome(ai, 4.0, 0.3)
	check(engage.cost < cover.cost, "健康敌人可选择立即交火而非无条件躲藏")
	ai.risk = 6.0
	var hurt_engage: Dictionary = selector.score_outcome(ai, 0.0, 4.0)
	var hurt_cover: Dictionary = selector.score_outcome(ai, 4.0, 0.3)
	check(hurt_cover.cost < hurt_engage.cost, "相同几何下风险厌恶增大可改变选择")
	check(hurt_cover.exposed_seconds == cover.exposed_seconds, "风险倾向不改变遮挡几何")
	var bounded: Dictionary = selector.score_outcome(ai, 40.0, 40.0, 40.0)
	check(bounded.unavailable_seconds == 4.0 and bounded.exposed_seconds == 8.0 and bounded.information_loss == 4.0, "观察时长一致，近距离空间风险保留两倍权重")
	check(selector.score_outcome(ai, 2.0, 0.5).cost < selector.score_outcome(ai, 4.0, 0.5).cost, "相同路线风险时提前恢复火力有收益")
	check(selector.score_outcome(ai, 4.0, 0.5, 0.0).cost < selector.score_outcome(ai, 4.0, 0.5, 4.0).cost, "失视时探索优于同风险静止等待")
	var body := Node.new()
	var a := {"id": &"reload", "plan": &"on_way", "cost": 3.0, "destination": {"hide": Vector3.ONE, "body": body}}
	var b := a.duplicate(true)
	b.cost = 2.0
	check(selector.same_option(a, b), "重新评估同一固定目的地保持身份")
	b.destination.hide = Vector3.RIGHT
	check(not selector.same_option(a, b), "同动作换目的地属于切换")
	b = a.duplicate(true)
	b.plan = &"after_cover"
	check(not selector.same_option(a, b), "不同换弹时机属于切换")
	check(selector.choose_option([a, b, {"id": &"engage", "cost": 1.0}]).id == &"engage", "换弹与其他行动共同竞争")
	check(selector.choose_option([]).is_empty(), "空候选安全返回")
	ai.actor = Body.new()
	root.add_child(ai.actor)
	var path := PackedVector3Array([Vector3.ZERO, Vector3(8, 0, 0)])
	var fast: Dictionary = selector.assess_route(ai, path, Vector3.ZERO, 2.0, 0.0)
	var reload_move: Dictionary = selector.assess_route(ai, path, Vector3.ZERO, 2.0, 2.0)
	check(is_equal_approx(fast.seconds, 4.0) and is_equal_approx(reload_move.seconds, 5.0), "换弹期间慢移，完成后恢复动作速度")
	check(is_equal_approx(fast.exposure, 4.0) and is_equal_approx(reload_move.exposure, 4.0), "长路线只计共同观察窗内暴露")
	var slow: Dictionary = selector.assess_route(ai, path, Vector3.ZERO, 0.5, 2.0)
	check(is_equal_approx(slow.seconds, 16.0), "原本慢移动作在换弹期间不被加速")
	var unknown: Dictionary = selector.assess_route(ai, path, Vector3.INF, 2.0, 0.0)
	check(unknown.exposure == 0.0, "没有已知威胁不虚构路线风险")
	ai.actor.free()
	body.free()
	ai.free()
	await check_scene(selector)
	print("Utility score: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_scene(selector: RefCounted) -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var arena = scene.get_node("Arena")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	ai.cover_selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	for frame in range(5):
		await physics_frame
	ai.is_alerted = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	ai.has_visual_memory = true
	enemy.global_position = arena.to_global(Vector3(-5, 0, 2.5))
	enemy.ammo.magazine_rounds = 0
	ai.utility_unseen_seconds = 2.0
	for frame in range(60):
		await physics_frame
		selector.advance_evaluation(ai, false)
	var target_before: Vector3 = ai.agent.target_position
	var state_before: int = ai.state
	var options: Array = selector.assess_options(ai, false)
	check(ai.agent.target_position == target_before and ai.state == state_before and not enemy.ammo.is_reloading, "候选评估不修改导航状态或开始换弹")
	check(options.any(func(option): return option.id == &"reload" and option.plan == &"here"), "实际场景有原地换弹候选")
	check(options.any(func(option): return option.id == &"cover"), "实际掩体行动参与同一比较")
	check(not options.any(func(option): return option.id == &"engage"), "失视时不把普通交火当可持续行动")
	player.global_position += Vector3(0, 0, -3)
	var hidden_moved: Array = selector.assess_options(ai, false)
	var unchanged: bool = options.size() == hidden_moved.size()
	for index in range(mini(options.size(), hidden_moved.size())):
		unchanged = unchanged and selector.same_option(options[index], hidden_moved[index]) and is_equal_approx(options[index].cost, hidden_moved[index].cost)
	check(unchanged, "隐藏玩家移动不改变已知威胁评分")
	var destination: Dictionary = {}
	for option: Dictionary in options:
		if option.id == &"cover":
			destination = option.destination
			break
	if not destination.is_empty():
		ai.cover.start_reload_transfer(destination, ai.last_known_position)
		var continued: Array = selector.assess_options(ai, false)
		check(continued.any(func(option): return option.id == &"cover" and selector.same_option(option, {"id": &"cover", "destination": destination})), "当前准确躲藏目的地重新加入候选")
		ai.cover.reset()
	# 三种计划均可生成，但只有统一选择器决定获胜者。
	check(options.any(func(option): return option.get("plan") == &"after_cover") and options.any(func(option): return option.get("plan") == &"on_way"), "同一场景生成三种换弹时机")
	var allowed: Array = ai.training.allowed_actions.duplicate()
	ai.training.allowed_actions.clear()
	var restricted: Array = selector.assess_options(ai, true)
	check(restricted.size() == 1 and restricted[0].id == &"reload" and restricted[0].plan == &"here", "训练权限排除战术行动但不撤销兵种基础换弹")
	ai.training.allowed_actions.assign(allowed)
	enemy.ammo.magazine_rounds = enemy.weapon.magazine_capacity
	ai.utility_suppression_pending = true
	var suppressed = ai.actions[&"suppression"]
	var suppression_state: bool = suppressed.is_active()
	var suppression_target: Vector3 = suppressed.aim_point
	selector.assess_options(ai, false)
	check(suppressed.is_active() == suppression_state and suppressed.aim_point == suppression_target, "压制候选查询不启动行动或改写瞄准点")
	ai.combat_type = ai.CombatType.MELEE
	var melee: Array = selector.assess_options(ai, true)
	check(not melee.any(func(option): return option.id in [&"reload", &"cover", &"attack_position", &"suppression", &"exit_suppression"]), "近战兵种不参与无法执行的枪械与躲藏方案")
	scene.queue_free()
	await process_frame

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
