extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(108)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	Fixture.configure_timing(enemy)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	var search = ai.actions[&"search"]
	search.tracking_cheat_enabled = false
	search.debug_tracking_cheat = false
	ai.cover_selection.debug_cover_selection = false
	enemy.global_position = Vector3(18, 0, 0)
	player.global_position = Vector3(21, 0, 0)
	for frame in 5: await physics_frame
	for frame in 120:
		if ai.context.environment_ready(): break
		await physics_frame
	enemy.look_at(player.global_position)
	ai._physics_process(1.0 / 60.0)
	check(ai.context.environment_ready() and ai.perception.can_see_player() and ai.has_visual_memory, "真实目击建立交战记忆，区域导航已就绪")
	var remembered: Vector3 = ai.last_seen_position
	# 玩家留在战斗区但离开视距，保留真实地面观察来验证完整覆盖换轮。
	var sight: float = ai.perception.sight_distance
	var awareness: float = ai.perception.close_awareness_radius
	ai.perception.sight_distance = 4.0
	ai.perception.close_awareness_radius = 0.0
	player.global_position = Vector3(31, 0, 5)
	ai.reset_actions()
	ai.utility_unseen_seconds = 30.0
	ai.utility_threat_age_seconds = 30.0
	search.search_seconds = 0.05
	search.search_radius = 1.5
	search.begin_search()
	check(not ai.perception.can_see_player(), "玩家仍在战斗区但实际不可见，搜索地面观察仍正常工作")
	var old_scale := Engine.time_scale
	Engine.time_scale = 6.0
	var rounds := 0
	var stayed_alert := true
	var stayed_in_area := true
	var travelled := 0.0
	var peak_usec := 0
	for frame in 1800:
		await physics_frame
		var before: float = search.get_search_coverage()
		var position: Vector3 = enemy.global_position
		var started := Time.get_ticks_usec()
		ai._physics_process(enemy.get_physics_process_delta_time())
		peak_usec = maxi(peak_usec, Time.get_ticks_usec() - started)
		travelled += enemy.global_position.distance_to(position)
		stayed_alert = stayed_alert and ai.is_alerted and ai.has_visual_memory and ai.state != ai.State.PATROL and ai.state != ai.State.IDLE
		if search.search_current_target_active:
			stayed_in_area = stayed_in_area and ai.context._horizontal_distance_between(search.search_current_target, remembered) <= search.search_radius + 0.001
		if before >= search.search_coverage_goal and search.get_search_coverage() < before: rounds += 1
		if not stayed_alert: break
		if rounds >= 2 and search.search_current_target_active: break
	Engine.time_scale = old_scale
	check(stayed_alert and ai.is_alerted, "原Utility实际运行跨过搜索总时限，全程保持警戒而不巡逻")
	check(rounds >= 2 and travelled > 3.0 and search.search_current_target_active, "无提示也实际走完至少两轮覆盖，并继续下一轮搜寻")
	check(search.search_elapsed_seconds > 1.0 and is_inf(search.search_timer), "交战搜索不受旧总时限限制，换轮不清零累计搜索时间")
	check(stayed_in_area and ai.last_seen_position == remembered and ai.last_known_position == remembered, "持续搜索保持已知区域，不刷新失视玩家的坐标")
	check(peak_usec < 20000, "连续搜寻的完整AI循环保留20毫秒门槛")
	print("[SearchPersistence] rounds=", rounds, " travelled=", travelled, " peak_usec=", peak_usec)

	# 覆盖完成边界保留计时衰减，不把下一轮当作刚刚失视。
	search.search_hint_decay_mode = search.SearchHintDecayMode.EXPONENTIAL_TIME
	search.search_elapsed_seconds = 23.0
	search.search_hint_timer = 0.4
	var probability: float = search.get_current_search_hint_chance()
	var age: float = ai.utility_unseen_seconds
	search.coverage.uncovered.clear()
	search.search_current_target_active = false
	search.search_is_pausing = false
	search._process_search(0.01)
	check(ai.is_alerted and ai.has_visual_memory and search.investigation_phase == ai.State.SEARCH, "覆盖达标只开始下一轮，不丢弃战斗记忆")
	check(search.search_elapsed_seconds >= 23.0 and search.search_hint_timer <= 0.4 and search.get_current_search_hint_chance() <= probability, "换轮不恢复提示概率、不返还提示间隔")
	check(ai.utility_unseen_seconds == age and search.movement_multiplier() <= 1.0, "换轮不刷新真实目击年龄、不重新获得快速追查")
	check(search.coverage.sample_count > 0 and search.get_search_coverage() < search.search_coverage_goal, "新一轮重新核实区域，没有沿用旧覆盖直接反复结束")
	search.cancel(&"switch")
	var elapsed: float = search.search_elapsed_seconds
	search.begin({"destination": {}}, false)
	check(ai.is_alerted and search.search_elapsed_seconds == elapsed, "普通动作切换保留持续搜索与衰减进度")

	# 区域完全不可达时保留警戒并间隔重试，避免每帧重建搜索网格。
	ai.last_seen_position = Vector3(1000, 0, 1000)
	ai.last_known_position = ai.last_seen_position
	search.begin_search()
	check(search.coverage.sample_count == 0, "无可达区域用例确实没有合法地面样本")
	var retries := 0
	stayed_alert = true
	for frame in 120:
		var pause: float = search.search_pause_timer
		search._process_search(1.0 / 60.0)
		if search.search_pause_timer > pause: retries += 1
		stayed_alert = stayed_alert and ai.is_alerted and ai.has_visual_memory
	check(stayed_alert and retries > 0 and retries <= 4, "无可达位置时保持警戒并有间隔重试，不忙循环或退回巡逻")
	ai.last_seen_position = remembered
	ai.last_known_position = remembered
	search.begin_search()
	search.search_is_pausing = false
	search._process_search(0.01)
	check(search.search_current_target_active, "后续出现可用区域时恢复合法搜索目标")
	search.search_target_timer = 0.0
	search._process_search(0.01)
	check(ai.is_alerted and not search.search_current_target_active and search.search_is_pausing, "当前路段超时仍跳过失败点，持续警戒不会变成无限卡住")
	search.begin_tracking_or_search(false)
	search.track_timer = 0.0
	search._process_track(0.01)
	check(ai.is_alerted and search.investigation_phase == ai.State.SEARCH, "沿线调查超时仍转入区域搜索，不解除警戒")

	# 没有发生视觉接敌的声音调查仍可正常结束。
	enemy.reset_target()
	search.investigate_noise(remembered, true)
	search.begin_search()
	search._process_search(0.1)
	check(not ai.has_visual_memory and not ai.is_alerted and ai.state == ai.State.IDLE, "纯声音调查沿用原结束规则，不无故永久进入战斗警戒")

	# 再次真实目击恢复接敌，真正的死亡和区域复位仍清理记忆。
	ai.perception.sight_distance = sight
	ai.perception.close_awareness_radius = awareness
	enemy.global_position = Vector3(18, 0, 0)
	player.global_position = remembered
	for frame in 3: await physics_frame
	enemy.look_at(player.global_position)
	ai._physics_process(1.0 / 60.0)
	check(ai.context.sees_player and ai.has_visual_memory and search.investigation_phase == -1, "重新目击玩家后原交战逻辑接管并清理搜索进度")
	search.begin_search()
	enemy.receive_hit(100000.0)
	check(search.coverage.sample_count == 0 and search.investigation_phase == -1, "死亡仍清理持续搜索执行与覆盖进度")
	enemy.reset_target()
	check(not ai.is_alerted and not ai.has_visual_memory and search.search_elapsed_seconds == 0.0, "真实复位仍清理警戒和搜索记忆")
	ai.context.update_evidence(0.0, true)
	search.begin_search()
	player.global_position = Vector3.ZERO
	for frame in 5: await physics_frame
	check(not ai.is_alerted and not ai.has_visual_memory and search.coverage.sample_count == 0, "离开战斗区继续遵守原场景复位规则")
	print("SEARCH PERSISTENCE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
