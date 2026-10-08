extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	Fixture.configure_timing(enemy)
	ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	var search = ai.actions[&"search"]
	enemy.global_position = Vector3(18, 0, 0)
	player.global_position = Vector3(30, 0, 5)
	for frame in 5: await physics_frame
	# 导航异步同步的时间不固定；先确认本区域就绪，再验证具体调查落点。
	for frame in 60:
		if ai.context.environment_ready(): break
		await physics_frame
	check(ai.context.environment_ready(), "调查用例开始前本区域导航与出生校验已就绪")
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = Vector3(21, 0, 0)
	ai.last_known_position = ai.last_seen_position
	ai.last_seen_direction = Vector3.RIGHT
	ai.context.observed_velocity = Vector3(2, 0, 0)
	ai.utility_unseen_seconds = 0.1
	search.begin_tracking_or_search(false)
	check(search.movement_multiplier() > 1.0, "刚失视时保留快速接敌，不立即变成慢速调查")
	check(search.suspected_position.distance_to(ai.last_seen_position) < 0.8, "无提示时先确认最后目击附近，不直接跳过失视位置")
	var target: Vector3 = search.suspected_position
	var speed: float = search.movement_multiplier()
	var timer: float = search.track_timer
	ai.utility_unseen_seconds = 30.0
	search.collect_candidates(false)
	check(search.suspected_position == target and search.movement_multiplier() == speed and search.track_timer == timer, "已承诺的短路段不会因记忆跨期或候选评估中途改目标、减速或续时")
	search.track_timer = 0.0
	search._process_track(0.01)
	check(search.investigation_phase == ai.State.SEARCH and search.movement_multiplier() <= 1.0, "旧线索的快速路段到时后退出，不能无限续追")
	search.reset()
	ai.utility_unseen_seconds = 0.1
	search.investigate_noise(Vector3(21, 0, 1), true)
	check(is_equal_approx(search.movement_multiplier(), search.track_move_speed_multiplier), "声音调查保持原速度，不借旧战斗记忆无故冲刺")
	search.reset()
	check(search.investigation_phase == -1 and not search.has_suspected_position, "复位清理调查目标与阶段")
	search.noise_search_origin = Vector3.INF
	ai.utility_unseen_seconds = 5.0
	search.begin_tracking_or_search(false)
	check(is_equal_approx(search.movement_multiplier(), 1.0), "快速追查期结束后先保持正常步速重点查找")
	search.reset()
	ai.utility_unseen_seconds = 12.0
	search.begin_tracking_or_search(false)
	check(is_equal_approx(search.movement_multiplier(), search.track_move_speed_multiplier), "陈旧目击不重新获得快速追查")
	search.reset()
	ai.utility_unseen_seconds = 0.1
	search.begin_tracking_or_search(false)
	var first: Vector3 = search.suspected_position
	enemy.global_position = first
	await physics_frame
	search._process_track(0.01)
	check(search.investigation_phase == ai.State.TRACK and search.suspected_position.x > first.x + 1.0, "确认失视位置后再沿真实目击方向接续下一段")
	var next: Vector3 = search.suspected_position
	player.global_position = Vector3(29, 0, -4)
	await physics_frame
	var before_timer: float = search.track_timer
	search.collect_candidates(false)
	check(search.suspected_position == next and search.track_timer == before_timer, "移动隐藏玩家与反复估价不更新轨迹或刷新执行计时")
	search.track_timer = 0.0
	search._process_track(0.01)
	check(search.investigation_phase == ai.State.SEARCH, "沿线调查扑空后进入有限区域，不反复追同一条推测轨迹")
	await _check_exits(enemy, ai, player, search)
	await _check_live(enemy, ai, player, false)
	await _check_live(enemy, ai, player, true)
	var settings = load("res://scripts/enemy/config/search_settings.gd").new()
	settings.combat_pursuit_seconds = 3.0
	settings.combat_pursuit_speed_multiplier = 1.7
	settings.focused_search_seconds = 7.0
	settings.focused_search_speed_multiplier = 0.9
	settings.focused_search_pause_seconds = 0.2
	DirAccess.make_dir_recursive_absolute("res://logs")
	var saved: Error = ResourceSaver.save(settings, "res://logs/search_pursuit_settings.tres")
	var restored = load("res://logs/search_pursuit_settings.tres")
	check(saved == OK and restored.combat_pursuit_seconds == 3.0 and is_equal_approx(restored.combat_pursuit_speed_multiplier, 1.7) and restored.focused_search_seconds == 7.0 and is_equal_approx(restored.focused_search_speed_multiplier, 0.9) and is_equal_approx(restored.focused_search_pause_seconds, 0.2), "追查与重点搜索参数保存重载并保留明确覆盖")
	search = ai.actions[&"search"]
	search.begin_tracking_or_search(false)
	var interrupted_target: Vector3 = search.utility_destination()
	var interrupted_time: float = search.track_timer
	var interrupted_speed: float = search.movement_multiplier()
	search.cancel(&"switch")
	search.begin({"destination": {}}, false)
	check(search.utility_destination() == interrupted_target and search.track_timer == interrupted_time and search.movement_multiplier() == interrupted_speed, "普通动作切换保留同一调查路段，不重选目标或返还时限")
	ai.unit_type.profile.default_behaviors = ai.unit_type.profile.default_behaviors.filter(func(action): return action.action_id != &"search")
	ai.refresh_configuration(true)
	check(not ai.actions.has(&"search") and not search._running and search._segment_speed < 0.0 and search._trail_pending.is_empty() and search.coverage.focus_points.is_empty(), "撤销搜索权限清理追查速度、待查轨迹与重点出口")
	print("SEARCH PURSUIT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _check_exits(enemy, ai, player, search) -> void:
	enemy.reset_target()
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.utility_unseen_seconds = 0.1
	var cover = ai.navigation_region.get_node("Environment/CoverA")
	var box = cover.get_node("CollisionShape3D")
	var center: Vector3 = box.global_position
	center.y = 0.0
	enemy.global_position = center + Vector3(3.8, 0, 0)
	ai.last_seen_position = center - Vector3(1.3, 0, 0)
	ai.last_known_position = ai.last_seen_position
	ai.last_seen_direction = Vector3.FORWARD
	ai.context.observed_velocity = Vector3.FORWARD * 2.0
	enemy.look_at(ai.last_seen_position)
	for frame in 3: await physics_frame
	search.begin_search()
	check(search.coverage.focus_points.size() == 2, "最后目击附近的原掩体提供当前面的两个出口作为重点")
	var points: Array[Vector3] = search.coverage.focus_points.duplicate()
	var samples: int = search.coverage.sample_count
	var original_pending: Array[Vector3] = search.coverage.pending.duplicate()
	var first: Dictionary = search.coverage.take_next(search.predicted_position(), true)
	check(not first.is_empty() and first.position.z < center.z - 2.0, "先检查最后运动方向上的可达出口，不随机选另一边")
	check(search.coverage.sample_count == samples and search.coverage.pending == original_pending, "优先出口不改变原地面覆盖率分母，也不提前算作搜过")
	var second: Dictionary = search.coverage.take_next(search.predicted_position(), true)
	check(not second.is_empty() and second.position.z > center.z + 2.0 and search.coverage.focus_points.is_empty(), "第一侧核实后转向另一侧，不反复选择同一个重点")
	var peak_usec := 0
	var no_checked_points: Array[Vector3] = []
	for frame in 45:
		await physics_frame
		var started := Time.get_ticks_usec()
		search.coverage.prepare_focus(no_checked_points)
		search.coverage.take_next(search.predicted_position(), true)
		peak_usec = maxi(peak_usec, Time.get_ticks_usec() - started)
	check(peak_usec < 20000, "出口准备和真实导航比较保留20毫秒门槛")
	search.coverage.prepare_focus(no_checked_points)
	var target: Dictionary = search.coverage.take_next(search.predicted_position(), true)
	player.global_position = center - Vector3(2.0, 0, 1.0)
	await physics_frame
	search.coverage.prepare_focus(no_checked_points)
	var moved: Dictionary = search.coverage.take_next(search.predicted_position(), true)
	check(not ai.perception.can_see_player() and target == moved, "隐藏玩家移动不改变重点出口及导航路径")
	if not first.is_empty():
		var checked_points: Array[Vector3] = [first.position]
		search.coverage.prepare_focus(checked_points)
		check(not search.coverage.focus_points.any(func(point): return point.distance_to(first.position) < 0.75), "已实际核实的轨迹位置不再加入同一轮重点出口")
	if not points.is_empty():
		var blocker := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.2, 2.0, 1.2)
		collision.shape = shape
		blocker.add_child(collision)
		root.add_child(blocker)
		blocker.global_position = points[0] + Vector3.UP
		await physics_frame
		search.coverage.prepare_focus(no_checked_points)
		var unblocked: Dictionary = search.coverage.take_next(search.predicted_position(), true)
		check(not unblocked.is_empty() and unblocked.position.distance_to(points[0]) > 0.75, "动态封堵出口后选择剩余可走路线")
		blocker.queue_free()
		await physics_frame
	ai.utility_unseen_seconds = 30.0
	search.begin_search()
	check(search.coverage.focus_points.is_empty() and is_equal_approx(search.movement_multiplier(), search.search_move_speed_multiplier), "旧目击只继续原有限区域搜索，不重建出口追查")
	print("PURSUIT EXITS peak_usec=", peak_usec)

func _check_live(enemy, ai, player, melee: bool) -> void:
	enemy.reset_target()
	Fixture.configure_timing(enemy)
	ai.training.profile.selected_tactics.clear()
	ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	if melee: enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.refresh_configuration(true)
	if melee: enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	player.health.debug_invincible = true
	enemy.global_position = Vector3(20, 0, 2)
	player.global_position = Vector3(18, 0, 5.4)
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	var lost := false
	var saw := false
	var fast := false
	var recovered := false
	var attacked := false
	var attacks_at_recovery := 0
	var peak_usec := 0
	for frame in 1500:
		await physics_frame
		if frame >= 30 and frame < 66:
			player.global_position.x = lerpf(18.0, 15.0, float(frame - 29) / 36.0)
		elif frame >= 66 and frame < 102:
			player.global_position.z = lerpf(5.4, 2.4, float(frame - 65) / 36.0)
		var started := Time.get_ticks_usec()
		ai._physics_process(1.0 / 60.0)
		peak_usec = maxi(peak_usec, Time.get_ticks_usec() - started)
		saw = saw or ai.context.sees_player
		if saw and not ai.context.sees_player:
			lost = true
			fast = fast or (ai.utility_current.get("id") == &"search" and Vector2(enemy.velocity.x, enemy.velocity.z).length() > enemy.move_speed * 1.1)
		elif lost:
			if not recovered: attacks_at_recovery = enemy.melee_count if melee else enemy.shot_count
			recovered = true
			attacked = (enemy.melee_count if melee else enemy.shot_count) > attacks_at_recovery
		if frame >= 102 and recovered and attacked: break
	check(saw and lost and fast, "真实交战失视后自主选中搜索并快速移动，兵种近战=" + str(melee))
	check(recovered and attacked, "关闭提示与听觉后绕墙恢复目击并接回攻击，兵种近战=" + str(melee))
	check(peak_usec < 20000, "完整自主追查保留20毫秒决策执行门槛，兵种近战=" + str(melee))
	print("PURSUIT LIVE melee=", melee, " peak_usec=", peak_usec)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
