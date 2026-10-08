extends SceneTree

var checks := 0
var failures := 0

class FixedOptions extends "res://scripts/enemy/enemy_action_selector.gd":
	var choices: Array[Dictionary] = []
	func assess_options(_ai: Node, _sees: bool) -> Array[Dictionary]:
		return choices

# 强制所有带误差位置不可用，验证不会退回真实坐标。
class RejectedHints extends "res://scripts/enemy/actions/enemy_search.gd":
	var used_exact_fallback := false
	func _set_suspected_position_from_raw(_point: Vector3, _snap: float) -> bool:
		return false
	func _set_suspected_position_relaxed(_point: Vector3) -> bool:
		used_exact_fallback = true
		return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(82)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	ai.cover_selection.debug_cover_selection = false
	ai.actions[&"search"].debug_tracking_cheat = false
	player.get_node("Health").debug_invincible = true
	enemy.global_position = Vector3(18, 0, 0)
	player.global_position = Vector3(20, 0, 2.5)
	for f in range(5): await physics_frame
	# 主导航和竞技场连接异步同步；首个物理帧不保证目标区域已可达。
	for frame in range(120):
		var path := NavigationServer3D.map_get_path(ai.agent.get_navigation_map(), enemy.global_position, Vector3(22, 0, 0), true, ai.agent.navigation_layers)
		if not path.is_empty() and ai.context._horizontal_distance_between(path[-1], Vector3(22, 0, 0)) < 0.2: break
		await physics_frame
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	var search = ai.actions[&"search"]
	check(ai.context.has_method("observe_visual_motion"), "连续真实目击支持短时运动估计")
	if ai.context.has_method("observe_visual_motion"):
		ai.context.observe_visual_motion(Vector3.ZERO, 1.0 / 60.0, false)
		for f in range(60):
			ai.context.observe_visual_motion(Vector3(0.02, 0, 0), 1.0 / 60.0, true)
		check(ai.last_seen_direction.dot(Vector3.RIGHT) > 0.95, "每帧不足0.05米的慢走仍能记录方向")
		check(search.observed_velocity.x > 1.0 and search.observed_velocity.x < 1.3, "速度估计来自位移与经过时间")
		for f in range(90): ai.context.observe_visual_motion(Vector3.ZERO, 1.0 / 60.0, true)
		check(ai.last_seen_direction.is_zero_approx(), "目击玩家停下后不会永久沿用旧方向")
		ai.context.observe_visual_motion(Vector3(30, 0, 0), 0.1, false)
		check(search.observed_velocity.is_zero_approx(), "重新目击不把墙后移动当作观察轨迹")

	ai.last_seen_direction = Vector3.RIGHT
	search.tracking_cheat_enabled = false
	search.begin_tracking_or_search(false)
	var predicted: Vector3 = search.suspected_position
	player.global_position += Vector3(0, 0, 1)
	check(search.suspected_position == predicted, "隐藏玩家移动不更新现有推测快照")
	# 给真实搜索选择入口提供两个可达候选：近处在后方，远处在轨迹前方。
	ai.last_seen_position = Vector3(20, 0, 0)
	ai.last_known_position = ai.last_seen_position
	ai.utility_unseen_seconds = 0.5
	search.begin_search()
	search.coverage.pending.assign([Vector3(18, 0, 0), Vector3(22, 0, 0)])
	search.coverage.uncovered.assign(search.coverage.pending)
	search.coverage.sample_count = 2
	check(search._advance_systematic_search_target() and search.search_current_target.x > 20, "先检查轨迹前方，不被较近的后方点吸引")
	if search.has_method("_search_point_cost"):
		var fresh_forward: float = search._search_point_cost(Vector3(22, 0, 0))
		var fresh_back: float = search._search_point_cost(Vector3(18, 0, 0))
		ai.utility_unseen_seconds = 30.0
		check(search._search_point_cost(Vector3(18, 0, 0)) - search._search_point_cost(Vector3(22, 0, 0)) < fresh_back - fresh_forward, "失视越久，轨迹方向偏好越弱")

	# 概率100%时也不能在走到观察点之前更新快照。
	search.tracking_cheat_enabled = true
	search.search_hint_chance = 1.0
	search.search_hint_decay_mode = search.SearchHintDecayMode.NONE
	search.search_hint_timer = 0.0
	search.search_is_pausing = false
	search._process_search(0.01)
	check(ai.state == ai.State.SEARCH and search.search_current_target_active, "途中概率提示不打断当前调查段")
	# 从同一轮区域搜索进入提示追踪，结束时不能重置覆盖和时间。
	search.begin_search()
	search.search_elapsed_seconds = 7.0
	search._mark_search_coverage(ai.last_seen_position)
	var uncovered: Array = search.coverage.uncovered.duplicate()
	var sample_count: int = search.coverage.sample_count
	search._set_suspected_position_from_raw(Vector3(21, 0, 1), 2.0)
	search._start_track_to_suspected()
	search.track_timer = 0.0
	search._process_track(0.01)
	check(search.coverage.sample_count == sample_count and search.coverage.uncovered == uncovered, "提示追踪返回后保留本轮未覆盖区域")
	check(search.search_elapsed_seconds >= 7.0, "提示不重置搜索累计时间和衰减")
	var rejected := RejectedHints.new()
	rejected.setup(ai.context, &"search")
	rejected.action_id = &"search"
	check(not rejected._try_tracking_cheat_hint(1.0) and not rejected.used_exact_fallback, "误差位置全失败时不读取真实位置作回退")

	# 使用真实空间候选验证：尚未目击，不能算作可以攻击的站位。
	var attack = load("res://resources/enemy/actions/attack_position.tres")

	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, attack.action_id, true)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"attack_position", true)
	ai.last_known_position = Vector3(20, 0, 2.5)
	for f in range(65):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, true)
	var visible_options: Array = ai.action_selector.assess_options(ai, true)
	# 该方向未必有部分遮身的优质点；正例由 attack_point_validation_test 的真实几何覆盖。
	var attack_options: Array = visible_options.filter(func(o): return o.id == &"attack_position")
	check(attack_options.all(func(o): return ai.cover_selection.assess_attack_point(o.destination.position, o.destination.body, ai.context.known_target_point(ai.last_known_position), ai.context.known_target_point(ai.last_known_position)).protection >= 0.2), "目击攻击候选必须满足部分遮身，不能强行加入无遮身点")
	var hidden_options: Array = ai.action_selector.assess_options(ai, false)
	check(not hidden_options.any(func(o): return o.id == &"attack_position"), "失视后的怀疑位置不能直接产生攻击占位")
	var covers: Array = visible_options.filter(func(o): return o.id == &"cover")
	check(not covers.is_empty(), "现场存在可用于切换复现的掩体")
	if not covers.is_empty():
		var evaluator = ai.action_selector
		var fixed := FixedOptions.new()
		var cover: Dictionary = covers[0].duplicate(true)
		cover.cost = -10.0
		fixed.choices = [{"id": &"search", "destination": {}, "cost": 20.0}, cover]
		ai.action_selector = fixed
		search.tracking_cheat_enabled = false
		search.begin_search()
		search._advance_systematic_search_target()
		search.search_is_pausing = false
		ai._start_utility_option(fixed.choices[0], false)
		var target: Vector3 = search.search_current_target
		ai.invalidate_utility()
		ai._update_utility_decision(1.0, false)
		check(ai.utility_current.id == &"search" and ai.agent.target_position == target, "普通分数变化不能打断架枪调查段")
		search._finish_current_search_point()
		search.search_pause_timer = 0.01
		search._process_search(0.02)
		check(not search.has_committed_segment(), "到点观察结束留出Utility重评边界")
		ai.invalidate_utility()
		ai._update_utility_decision(0.5, false)
		check(ai.utility_current.id == &"search", "段结束后同一份旧威胁不能把调查拉回躲藏")
		ai._start_utility_option(fixed.choices[0], false)
		search._advance_systematic_search_target()
		search.search_is_pausing = false
		search.search_seconds = 20.0
		search.search_timer = 12.0
		var old_target: Vector3 = search.search_current_target
		ai.context._investigate_attack(Vector3(22, 0, 1))
		ai.nearby_shot_pressure += 0.15
		ai.invalidate_utility()
		ai._update_utility_decision(0.5, false)
		check(ai.utility_current.id == &"search" and search.search_current_target == old_target, "单发近弹不从旧入口强制打断调查")
		check(search.search_timer == 12.0, "更新近弹威胁不清零本轮搜索剩余时间")
		ai.nearby_shot_pressure += 0.3
		ai.invalidate_utility()
		ai._update_utility_decision(0.5, false)
		check(ai.utility_current.id == &"cover", "明显新增连续近弹允许避险")
		ai._start_utility_option(fixed.choices[0], false)
		enemy.receive_hit(1.0)
		ai.invalidate_utility()
		ai._update_utility_decision(0.5, false)
		check(ai.utility_current.id == &"cover", "真实受伤可以打断调查并按Utility避险")
		ai._start_utility_option(fixed.choices[0], false)
		enemy.receive_hit(1.0, Vector3(23, 0, 1))
		fixed.choices = [fixed.choices[0]]
		ai.invalidate_utility()
		ai._update_utility_decision(0.5, false)
		preload("res://tests/enemy/enemy_fire_fixture.gd").tick_selected(ai, 0.01, false)
		check(ai.is_alerted and ai.state != ai.State.IDLE, "带攻击者位置的受伤不会恢复零计时搜索而立即丢失警戒")
		check(search.suspected_look_position.distance_to(ai.last_known_position) < 2.0, "受伤后调查新的已知攻击位置，不恢复旧猜测")
		# 有效调查不妨碍基础换弹，也不妨碍真正目击接管。
		var reload_choice := {"id": &"reload", "plan": &"here", "destination": {}, "cost": -20.0}
		fixed.choices.append(reload_choice)
		enemy.ammo.magazine_rounds = 0
		ai.invalidate_utility()
		ai._update_utility_decision(1.0, false)
		check(ai.utility_current.id == &"reload" and enemy.ammo.is_reloading, "搜索保持允许空匣换弹")
		ai._start_utility_option(fixed.choices[0], false)
		fixed.choices = [{"id": &"engage", "destination": {}, "cost": 0.0}]
		ai.invalidate_utility()
		ai._update_utility_decision(0.01, true)
		check(ai.utility_current.id == &"engage" and enemy.ammo.is_reloading, "真正目击立即接敌且不取消已开始换弹")
		ai.action_selector = evaluator

	# 提示成功后沿途仅使用快照；失败路线允许结束保持，不会卡到整轮搜索结束。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = enemy.weapon.magazine_capacity
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = Vector3(20, 0, 2.5)
	ai.last_known_position = ai.last_seen_position
	ai.last_seen_direction = Vector3.RIGHT
	search.tracking_cheat_enabled = true
	search.search_seconds = 0.0
	search.tracking_hint_error_radius = 1.25
	player.global_position = ai.last_seen_position
	for f in range(3): await physics_frame
	check(search._try_tracking_cheat_hint(1.0), "现有概率提示仍能产生带误差的可达目标")
	var hint: Vector3 = search.suspected_position
	var look: Vector3 = search.suspected_look_position
	search._start_track_to_suspected()
	player.global_position += Vector3(0, 0, 2)
	for f in range(65):
		await physics_frame
		if ai.state == ai.State.TRACK: search._process_track(1.0 / 60.0)
	check(search.suspected_position == hint and search.suspected_look_position == look, "提示追踪期间不跟随隐藏玩家移动")
	check(ai.state == ai.State.SEARCH and not search.has_committed_segment(), "TRACK实际无进展时解除保持并恢复区域搜索")
	# 完整AI循环实际走到调查点；没有新证据时不靠禁用掩体来避免切换。
	ai.reset_actions()
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = Vector3(20, 0, 2.5)
	ai.last_known_position = ai.last_seen_position
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	ai.utility_threat_age_seconds = 8.0
	search.tracking_cheat_enabled = false
	search.search_seconds = 0.0
	enemy.global_position = Vector3(18, 0, 0)
	check(search._set_suspected_position_from_raw(Vector3(21, 0, 1), 2.0), "实走存在可达调查目标")
	search._start_track_to_suspected()
	ai._start_utility_option({"id": &"search", "destination": {}, "cost": 0.0}, false)
	var walk_target: Vector3 = search.suspected_position
	var reached := false
	var interrupted := false
	var initial: Vector3 = enemy.global_position
	for f in range(600):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		reached = enemy.global_position.distance_to(walk_target) < 0.55
		if reached: break
		if ai.utility_current.get("id") != &"search":
			interrupted = true
			break
	check(reached and not interrupted and enemy.global_position.distance_to(initial) > 1.0, "真实AI架枪走到怀疑点，途中不切攻击占位或折返掩体")
	# 撤权/刷新可终止保持。
	ai.unit_type.profile.default_behaviors = ai.unit_type.profile.default_behaviors.filter(func(a): return a.action_id != &"search")
	ai.refresh_configuration(true)
	ai._physics_process(0.01)
	check(ai.utility_current.get("id") != &"search", "搜索权限撤销不会被调查保持困住")
	ai._reset_decisions()
	check(search.investigation_phase == -1 and search.observed_velocity == Vector3.ZERO, "刷新清除调查与轨迹缓存")

	print("SEARCH EVIDENCE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
