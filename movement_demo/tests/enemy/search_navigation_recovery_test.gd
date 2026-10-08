extends SceneTree

const LIVE_POSITION := Vector3(16.5115585, 0.0008413, 4.9022946)
const INVALID_MEMORY := Vector3(15.7548351, 0.0008413, -1.690755)
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(28)
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
	ai.actions[&"search"].tracking_cheat_enabled = false
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	player.global_position = Vector3(16.49831, 0, -2.924036)
	enemy.global_position = LIVE_POSITION
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = Vector3(18.867762, 0, -2.588767)
	ai.last_known_position = ai.last_seen_position
	ai.utility_unseen_seconds = 80.0
	ai.utility_threat_age_seconds = 80.0
	for frame in range(5): await physics_frame
	# 等竞技场连通路径实际就绪；map已有一次同步不代表本场景区域已提交。
	for frame in range(120):
		if not NavigationServer3D.map_get_path(ai.agent.get_navigation_map(), LIVE_POSITION, Vector3(18,0,0),true).is_empty(): break
		await physics_frame
	check(ai.is_arena_active(), "复现时玩家实际位于竞技场")
	check(ai.cover_selection._path_to(LIVE_POSITION, LIVE_POSITION).is_empty(), "现场脚下偏出导航约0.098米，严格路径检查失败")
	ai.actions[&"search"].begin_search()
	ai.actions[&"search"].search_pause_timer = 0.183333
	var remaining: int = ai.actions[&"search"].coverage.pending.size()
	check(remaining > 0, "脚下偏出导航但区域内仍存在可达搜索点")
	var option := search_option(ai)
	check(not option.is_empty(), "原地观察不依赖到脚下的导航路径，搜索仍能参选")
	check(ai.actions[&"search"].search_pause_timer == 0.183333 and ai.actions[&"search"].coverage.pending.size() == remaining, "候选评估不推进观察或消耗搜索点")
	# 原场景HIDE，Utility只剩掩体时无法让观察计时继续。
	for frame in range(60):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, false)
	var cover_choice: Dictionary = {}
	for candidate: Dictionary in ai.action_selector.assess_options(ai, false):
		if candidate.id == &"cover":
			cover_choice = candidate
			break
	check(not cover_choice.is_empty(), "复现场景存在真实掩体方案")
	if not cover_choice.is_empty():
		ai._start_utility_option(cover_choice, false)
		ai.actions[&"cover"].transfer.phase = ai.actions[&"cover"].transfer.Phase.HIDE
		ai.invalidate_utility()
		ai._update_utility_decision(1.0, false)
		check(ai.utility_current.get("id") == &"search", "旧威胁现场可从HIDE切回观察")
		preload("res://tests/enemy/enemy_fire_fixture.gd").tick_selected(ai, 0.1, false)
		check(ai.actions[&"search"].search_pause_timer < 0.183333, "搜索重新执行后观察计时实际推进")
	# 失效的记忆点不能禁用整个搜索动作；实际执行才重建附近区域。
	ai.reset_actions()
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = INVALID_MEMORY
	ai.last_seen_position = INVALID_MEMORY
	ai.last_seen_direction = Vector3.ZERO
	ai.utility_unseen_seconds = 100.0
	ai.utility_threat_age_seconds = 100.0
	check(ai.cover_selection._path_to(LIVE_POSITION, INVALID_MEMORY).is_empty(), "现场新记忆点偏离导航约0.5米")
	option = search_option(ai)
	check(not option.is_empty(), "没有已建搜索区域时，非法记忆点仍允许重新规划搜索")
	check(ai.actions[&"search"].investigation_phase == -1, "评估重规划候选不私自启动搜索")
	if not option.is_empty():
		ai._start_utility_option(option, false)
		preload("res://tests/enemy/enemy_fire_fixture.gd").tick_selected(ai, 0.01, false)
		check(ai.actions[&"search"].investigation_phase == ai.State.SEARCH and not ai.actions[&"search"].coverage.pending.is_empty(), "执行时生成记忆位置附近的可达区域")
	# 评分用的是旧非法记忆，但启动动作可能已经生成有效的轨迹预测点。
	var found_track := false
	for direction: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD, Vector3.LEFT]:
		ai.reset_actions()
		ai.is_alerted = true
		ai.has_visual_memory = true
		ai.last_known_position = INVALID_MEMORY
		ai.last_seen_position = INVALID_MEMORY
		ai.last_seen_direction = direction
		ai.actions[&"search"].observed_velocity = direction * 2.0
		option = search_option(ai)
		if option.is_empty(): continue
		ai._start_utility_option(option, false)
		if ai.state != ai.State.TRACK or ai.cover_selection._path_to(enemy.global_position, ai.actions[&"search"].utility_destination()).is_empty(): continue
		found_track = true
		var prediction: Vector3 = ai.actions[&"search"].utility_destination()
		preload("res://tests/enemy/enemy_fire_fixture.gd").tick_selected(ai, 0.01, false)
		check(ai.state == ai.State.TRACK and ai.actions[&"search"].utility_destination() == prediction, "旧恢复标记不能取消刚建立的有效预测追踪")
		break
	check(found_track, "非法旧记忆附近可以生成有效的新轨迹目标")
	# 当前搜索点后来失效：跳过它，但不把它误记为搜过，也不清空其余区域。
	ai.actions[&"search"].begin_search()
	ai.actions[&"search"].search_current_target = INVALID_MEMORY
	ai.actions[&"search"].search_current_target_active = true
	ai.actions[&"search"].search_is_pausing = false
	var coverage: float = ai.actions[&"search"].get_search_coverage()
	remaining = ai.actions[&"search"].coverage.pending.size()
	ai.utility_current = {"id": &"search", "destination": {}, "cost": 0.0}
	option = search_option(ai)
	check(not option.is_empty(), "正在执行的目标失效时搜索仍有恢复候选")
	if not option.is_empty():
		# 同一个search动作被保持时也必须处理恢复，不仅处理动作启动。
		ai.utility_current = option
		preload("res://tests/enemy/enemy_fire_fixture.gd").tick_selected(ai, 0.01, false)
		check(ai.actions[&"search"].search_current_target != INVALID_MEMORY and ai.actions[&"search"].search_current_target_active, "同一搜索动作内切换到可达替代目标")
		check(ai.actions[&"search"].get_search_coverage() == coverage and ai.actions[&"search"].coverage.pending.size() < remaining, "失败点不计覆盖且保留其余搜索进度")
		check(not ai.cover_selection._path_to(enemy.global_position, ai.actions[&"search"].search_current_target).is_empty(), "替代目标通过原有严格导航校验")
	var start: Vector3 = enemy.global_position
	for frame in range(240):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	check(enemy.global_position.distance_to(start) > 0.6, "完整AI从现场位置实际离开，继续寻找")
	# 本轮可用位置耗尽后保持交战警戒，观察后重建下一轮。
	ai.actions[&"search"].begin_search()
	ai.actions[&"search"].coverage.pending.clear()
	ai.actions[&"search"].coverage.uncovered.assign([INVALID_MEMORY])
	ai.actions[&"search"].coverage.sample_count = 1
	ai.actions[&"search"].search_current_target = INVALID_MEMORY
	ai.actions[&"search"].search_current_target_active = true
	ai.actions[&"search"].search_is_pausing = false
	option = search_option(ai)
	if not option.is_empty():
		ai.utility_current = option
		preload("res://tests/enemy/enemy_fire_fixture.gd").tick_selected(ai, 0.01, false)
	check(ai.is_alerted and ai.has_visual_memory and ai.state == ai.State.SEARCH
		and ai.actions[&"search"].is_observing() and ai.actions[&"search"].search_pause_timer >= 0.45,
		"无剩余可达位置时保持警戒并间隔重试，不每帧循环恢复")
	ai.is_alerted = true
	ai.unit_type.profile.default_behaviors = ai.unit_type.profile.default_behaviors.filter(func(a): return a.action_id != &"search")
	ai.refresh_configuration(true)
	check(search_option(ai).is_empty(), "恢复入口仍尊重搜索权限")
	print("SEARCH NAV RECOVERY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func search_option(ai: Node) -> Dictionary:
	for option: Dictionary in ai.action_selector.assess_options(ai, false):
		if option.id == &"search": return option
	return {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
