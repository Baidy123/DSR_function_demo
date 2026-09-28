extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(11)
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
	ai.search.tracking_cheat_enabled = false
	ai.search.debug_tracking_cheat = false
	player.get_node("Health").debug_invincible = true
	player.global_position = Vector3(18.585854, 0.001, 4.430427)
	enemy.global_position = Vector3(26.48409, 0.001, 4.78908)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	ai.utility_unseen_seconds = 4.0
	for f in range(5): await physics_frame
	# 搜寻被掩体打断后主状态仍可为TRACK，但公共导航目标已是掩体/脚下。
	ai.search._set_suspected_position_from_raw(ai.last_known_position, 2.0)
	ai.search._start_track_to_suspected()
	var expected: Vector3 = ai.search.suspected_position
	ai.cover.phase = ai.cover.Phase.HIDE
	ai.cover.hide_position = enemy.global_position
	ai.cover.active_cover_body = scene.get_node("Arena/NavigationRegion3D/Environment/CoverF")
	ai.utility_current = {"id": &"cover", "destination": {"hide": enemy.global_position, "body": ai.cover.active_cover_body}}
	ai.agent.target_position = enemy.global_position
	var from_cover := search_cost(ai)
	ai.agent.target_position = expected
	var from_search := search_cost(ai)
	check(is_finite(from_cover) and is_equal_approx(from_cover, from_search), "搜寻代价不受掩体重写公共导航目标影响")
	ai.agent.target_position = enemy.global_position
	ai._start_utility_option({"id": &"search", "destination": {}, "cost": from_cover}, false)
	check(ai.agent.target_position.is_equal_approx(expected), "恢复架枪搜寻继续原目标，不重抽路线")
	# 连续无人目击、无新来弹时，不能永远把旧威胁当作当前火力封锁。
	ai.reset_actions()
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	enemy.health = enemy.max_health * 0.05
	# 玩家已离开旧目击位置，不能让测试把重新目击后的合理退避当成停滞。
	player.global_position = Vector3(18, 0, -3)
	for f in range(3): await physics_frame
	check(ai.is_arena_active(), "旧威胁测试期间玩家仍在竞技场")
	var max_hide := 0.0
	var hide := 0.0
	var moved := false
	var start: Vector3 = enemy.global_position
	for f in range(2400):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if ai.cover.phase == ai.cover.Phase.HIDE: hide += 1.0 / 60.0
		else: hide = 0.0
		max_hide = maxf(max_hide, hide)
		moved = moved or enemy.global_position.distance_to(start) > 1.0
	check(max_hide < 30.0 and moved, "旧威胁没有新证据时不会连续躲藏30秒以上")
	print("HIDE longest=", max_hide)
	var remembered: Vector3 = ai.last_known_position
	ai.utility_threat_age_seconds = 12.0
	var old_risk: float = ai._reload_risk_aversion()
	ai.utility_threat_age_seconds = 0.0
	check(old_risk < ai._reload_risk_aversion() * 0.2 and ai.last_known_position == remembered, "旧威胁风险衰减，但不会删除位置记忆")
	ai.utility_threat_age_seconds = 12.0
	ai._investigate_attack(remembered)
	check(ai.utility_threat_age_seconds == 0.0, "新的有效来弹更新威胁时效")
	ai.utility_threat_age_seconds = 12.0
	enemy.receive_hit(1.0)
	check(ai.utility_threat_age_seconds == 0.0, "真正受伤即使没有攻击者坐标也恢复风险")
	print("UTILITY SEARCH COVER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func search_cost(ai: Node) -> float:
	for o: Dictionary in ai.action_selector.assess_options(ai, false):
		if o.id == &"search": return o.cost
	return INF

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
