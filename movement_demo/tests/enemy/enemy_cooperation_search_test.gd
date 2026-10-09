extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const Coverage = preload("res://scripts/enemy/services/enemy_search_coverage.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var arena = scene.get_node("Arena")
	var first = arena.get_node("Enemy")
	var second = load("res://scenes/enemy/enemy.tscn").instantiate()
	second.position = arena.to_local(Vector3(18, 0, 2))
	arena.add_child(second)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	var first_ai = first.get_node("AI")
	var second_ai = second.get_node("AI")
	for actor in [first, second]:
		var ai = actor.get_node("AI")
		ai.set_physics_process(false)
		Fixture.configure_timing(actor)
		ai.training.profile.selected_tactics.assign([&"cooperate"])
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.training.profile.set_setting(&"search", &"search_seconds", 0.2)
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.refresh_configuration(true)
		actor.debug_shooting = false
		ai.cover_selection.debug_cover_selection = false
		ai.cover_selection.debug_attack_points = false
	first.global_position = Vector3(18, 0, 0)
	player.global_position = Vector3(22, 0, 1)
	for frame in 10: await physics_frame
	check(first_ai.context.cooperation_enabled() and second_ai.context.cooperation_enabled(), "两个实例通过原训练装配获得合作权限")
	var first_search = first_ai.actions[&"search"]
	var second_search = second_ai.actions[&"search"]
	first_ai.context.cooperation_publish_execution({})
	second_ai.context.cooperation_publish_execution({})
	# 合作时世界格对齐；个人覆盖率仍由自己实际观察的样本决定。
	first_search.coverage.build(first_ai.context, Vector3(22, 0, 0), 2.0, 1.0, 0.65)
	second_search.coverage.build(second_ai.context, Vector3(22, 0, 0), 2.0, 1.0, 0.65)
	check(first_search.coverage.sample_count > 0 and first_search.coverage.pending == second_search.coverage.pending, "同一地区的合作地面采样精确对齐，不共享假想观察圆")
	await _check_negative_evidence(scene, first, second, player)

	# 只有 A 真正看到目标，B 朝向相反；通过自然感知和 Utility 进入团队调查。
	first.reset_target()
	second.reset_target()
	first.global_position = Vector3(18, 0, 0)
	second.global_position = Vector3(18, 0, 2)
	player.global_position = Vector3(22, 0, 1)
	first.look_at(player.global_position)
	second.look_at(second.global_position + Vector3.LEFT)
	for frame in 3: await physics_frame
	first_ai._physics_process(STEP)
	second_ai._physics_process(STEP)
	check(first_ai.has_visual_memory and second_ai.context.has_combat_contact() and not second_ai.has_visual_memory and not second_ai.context.sees_player, "队友目击触发团队接敌，但不伪造接收者的个人目击")
	var barrier := _wall(scene, Vector3(28, 1.5, 0), Vector3(0.2, 3, 20))
	player.global_position = Vector3(31, 0, 0)
	for frame in 3: await physics_frame
	var first_start: Vector3 = first.global_position
	var second_start: Vector3 = second.global_position
	var separate := false
	var stayed_alert := true
	var immutable := true
	var last_claim_count := -1
	for frame in 240:
		await physics_frame
		first_ai._physics_process(STEP)
		second_ai._physics_process(STEP)
		stayed_alert = stayed_alert and first_ai.is_alerted and second_ai.is_alerted
		if first_ai.utility_current.get("id") == &"search" and second_ai.utility_current.get("id") == &"search":
			if not first_search._search_claim.is_empty() and not second_search._search_claim.is_empty():
				separate = separate or first_search.utility_destination().distance_to(second_search.utility_destination()) > 0.9
		if frame == 60:
			last_claim_count = second_ai.context.cooperation_snapshot().claims.size()
			var target: Vector3 = second_search.utility_destination()
			var remaining: float = second_search.track_timer
			second_search.collect_candidates(false)
			second_search.collect_candidates(false)
			immutable = last_claim_count == second_ai.context.cooperation_snapshot().claims.size() and target == second_search.utility_destination() and remaining == second_search.track_timer
	check(separate, "正常 Utility 执行期间两人认领不同调查位置，没有挤向同一个线索点")
	check(first.global_position.distance_to(first_start) > 0.4 and second.global_position.distance_to(second_start) > 0.4, "两名敌人实际移动执行分工搜索")
	check(stayed_alert and second_ai.context.has_combat_contact() and not second_ai.has_visual_memory, "仅团队目击的敌人超过普通调查时限仍持续搜索，个人目击保持独立")
	check(immutable and last_claim_count >= 0, "反复收集候选不认领新任务、不重选目标或返还路段时限")
	for frame in 120:
		if not first_search._search_claim.is_empty(): break
		await physics_frame
		first_ai._physics_process(STEP)
		second_ai._physics_process(STEP)
	var token: Dictionary = first_search._search_claim.duplicate()
	check(not token.is_empty(), "取消验证前确实存在正在执行的搜索认领")
	first_search.cancel(&"switch")
	check(first_search._search_claim.is_empty(), "暂时切换动作释放搜索岗位，保留个人调查进度")
	if not token.is_empty():
		check(second_ai.context.cooperation_search_available(token.position, 0.1), "同伴取消后原调查位置可以重新认领")
	barrier.queue_free()
	print("ENEMY COOPERATION SEARCH: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _check_negative_evidence(scene, first, second, player) -> void:
	var a = first.get_node("AI").context
	var b = second.get_node("AI").context
	first.global_position = Vector3(19.2, 0, 0)
	first.look_at(Vector3(20, 0, 0))
	player.global_position = Vector3(22, 0, 0)
	var wall := _wall(scene, Vector3(20, 1.1, 0), Vector3(0.2, 2.2, 4))
	for frame in 3: await physics_frame
	var near := Vector3(19.2, 0, 0.5)
	var hidden := Vector3(20.8, 0, 0)
	var observed := Coverage.new()
	observed.context = a
	observed.search_coverage_radius = 2.0
	observed.pending.assign([near, hidden])
	observed.uncovered.assign(observed.pending)
	observed.sample_count = 2
	observed.mark(first.global_position)
	var reports: Array = b.cooperation_checked_points()
	check(reports.any(func(item): return item.position.is_equal_approx(near)) and not reports.any(func(item): return item.position.is_equal_approx(hidden)), "只广播实际看见的地面，隔墙样本不成为共享负证据")
	var received := Coverage.new()
	received.context = b
	received.search_origin = near
	received.pending.assign([near])
	received.uncovered.assign([near])
	received.sample_count = 1
	check(received.take_next(near).is_empty() and received.pending.has(near) and received.fraction() == 0.0, "暂时跳过友军刚检查的同一采样点，不虚增个人覆盖率或永久删除")
	a.cooperation.advance(3.1)
	var next: Dictionary = received.take_next(near)
	check(not next.is_empty() and next.position.is_equal_approx(near) and received.fraction() == 0.0, "负证据到期后同一地面恢复可调查，选中仍不等于实际观察")
	wall.queue_free()
	for frame in 3: await physics_frame

func _wall(scene: Node, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	scene.add_child(body)
	body.global_position = position
	return body

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
