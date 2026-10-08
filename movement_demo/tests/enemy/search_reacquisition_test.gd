extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const Coverage = preload("res://scripts/enemy/services/enemy_search_coverage.gd")
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
	Fixture.configure_timing(enemy)
	player.get_node("Health").debug_invincible = true
	ai.cover_selection.debug_cover_selection = false
	enemy.global_position = Vector3(18, 0, 0)
	player.global_position = Vector3(21, 0, 2)
	for frame in range(12): await physics_frame
	var search = ai.actions[&"search"]
	search.tracking_cheat_enabled = false
	search.lost_target_hint_chance = 0.0
	search.search_hint_chance = 0.0
	search.debug_tracking_cheat = false
	await _check_wall_coverage(scene, enemy, ai, player)
	_check_known_position(enemy, ai, player, search)
	await _check_area_observation(enemy, ai, player, search)
	for random_seed in [11, 82, 303]:
		await _check_live_search(enemy, ai, player, random_seed)
	await _check_live_search(enemy, ai, player, 82, true)
	print("SEARCH REACQUISITION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _check_wall_coverage(scene, enemy, ai, player) -> void:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 2.2, 4.0)
	collision.shape = shape
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = Vector3(20, 1.1, 0)
	enemy.global_position = Vector3(19.2, 0, 0)
	player.global_position = Vector3(22, 0, 0)
	for frame in range(3): await physics_frame
	var near := Vector3(19.2, 0, 0.5)
	var hidden := Vector3(20.8, 0, 0)
	var coverage := Coverage.new()
	coverage.context = ai.context
	coverage.search_coverage_radius = 2.0
	coverage.pending.assign([near, hidden])
	coverage.uncovered.assign(coverage.pending)
	coverage.sample_count = 2
	coverage.mark(enemy.global_position)
	check(not coverage.uncovered.has(near), "到达位置附近无遮挡地面正常计入覆盖")
	check(coverage.uncovered.has(hidden) and coverage.pending.has(hidden), "隔墙藏身点保留为未搜索目标")
	check(is_equal_approx(coverage.fraction(), 0.5), "覆盖率不能把隔墙地面当成已经确认")
	wall.queue_free()
	for frame in range(3): await physics_frame
	# 隐藏玩家的身体不能成为搜索地图的探针：环境相同，覆盖结果必须相同。
	player.global_position = Vector3(20, 0, 0)
	for frame in range(3): await physics_frame
	coverage.mark(enemy.global_position)
	check(coverage.uncovered.is_empty(), "墙移除后可覆盖，玩家身体不泄露隐藏位置")
	coverage.reset()
	check(coverage.pending.is_empty() and coverage.uncovered.is_empty(), "复位清理所有搜索覆盖进度")
	enemy.global_position = Vector3(21, 0, 0)
	enemy.look_at(Vector3(21, 0, -1))
	ai.state = ai.State.SEARCH
	var front := Vector3(21, 0, -2.5)
	var back := Vector3(21, 0, 2.5)
	coverage.search_coverage_radius = 4.0
	coverage.pending.assign([front, back])
	coverage.uncovered.assign(coverage.pending)
	coverage.sample_count = 2
	coverage.mark(enemy.global_position)
	check(not coverage.uncovered.has(front) and coverage.uncovered.has(back), "大覆盖半径仍保留实际视角之外的盲区")
	enemy.look_at(back)
	coverage.mark(enemy.global_position)
	check(coverage.uncovered.is_empty(), "转身后才能排除先前的背后盲区")
	check(not ai.perception.can_observe_position(Vector3(21, 0, 20)), "可观察地面查询仍受原感知距离限制")

func _check_known_position(enemy, ai, player, search) -> void:
	ai.reset_actions()
	enemy.global_position = Vector3(18, 0, 0)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = Vector3(21, 0, 2)
	ai.last_seen_position = ai.last_known_position
	ai.last_seen_direction = Vector3.ZERO
	search.begin_tracking_or_search(false)
	check(ai.state == ai.State.TRACK and search.has_suspected_position,
		"没有运动方向与提示时仍直接调查最后目击位置")
	check(search.has_suspected_position and search.suspected_position.distance_to(ai.last_seen_position) < 0.8,
		"静止目击的首个调查目标位于真实记忆附近")
	var remembered: Vector3 = search.suspected_position
	player.global_position = Vector3(29, 0, 4)
	search.begin_tracking_or_search(false)
	check(search.suspected_position.is_equal_approx(remembered), "隐藏玩家移动不改变无提示调查目的地")
	# 原导航东侧之外的预测不可达，但原目击位置仍在可达地面内。
	ai.last_seen_position = Vector3(32.5, 0, 0)
	ai.last_known_position = ai.last_seen_position
	ai.last_seen_direction = Vector3.RIGHT
	search.observed_velocity = Vector3(6, 0, 0)
	check(not search._set_suspected_position_from_raw(search.predicted_position(), 2.0), "预测回退场景确实包含地图外的推测终点")
	search.begin_tracking_or_search(false)
	check(ai.state == ai.State.TRACK and search.has_suspected_position
		and search.suspected_position.distance_to(ai.last_seen_position) < 0.8,
		"方向预测无效时回到可达的最后目击位置调查")
	search.reset()
	check(not search.has_suspected_position and search.investigation_phase == -1,
		"调查复位不残留旧目标或阶段")

func _check_area_observation(enemy, ai, player, search) -> void:
	seed(202)
	ai.reset_actions()
	enemy.global_position = Vector3(12, 0, 4.8)
	player.global_position = Vector3(23, 0, 0)
	for frame in range(4): await physics_frame
	ai.last_known_position = Vector3(12, 0, 5.5)
	var previous_radius: float = search.search_radius
	search.search_radius = 3.0
	search.begin_search()
	var origin: Vector3 = search.search_origin
	var samples: Array[Vector3] = []
	# 独立密采样，不使用搜索组件自己的采样网格来证明墙后覆盖。
	for x in range(-8, 9):
		for z in range(-8, 9):
			var point := origin + Vector3(x * 0.35, 0, z * 0.35)
			if point.distance_to(origin) > search.search_radius: continue
			var nav := NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), point)
			if ai.context._horizontal_distance_between(nav, point) > 0.1 or not ai.context.is_position_free(point): continue
			var path: PackedVector3Array = ai.cover_selection._path_to(enemy.global_position, point)
			if not path.is_empty(): samples.append(point)
	var sample_count := samples.size()
	var covered := 0
	var visited := 0
	var completed_round := false
	var next_round_started := false
	var peak_usec := 0
	var previous_scale := Engine.time_scale
	Engine.time_scale = 4.0
	for frame in range(1400):
		await physics_frame
		var before: float = search.get_search_coverage()
		var delta: float = enemy.get_physics_process_delta_time()
		var started := Time.get_ticks_usec()
		var direction: Vector3 = search._process_search(delta)
		peak_usec = maxi(peak_usec, Time.get_ticks_usec() - started)
		if ai.state != ai.State.SEARCH: break
		if before >= search.search_coverage_goal and search.get_search_coverage() < before:
			completed_round = true
		if completed_round and search.search_current_target_active:
			next_round_started = true
			break
		if search.get_search_coverage() > before:
			visited += 1
			for index in range(samples.size() - 1, -1, -1):
				if samples[index].distance_to(search.search_current_target) <= search.search_coverage_radius \
					and ai.cover_selection.has_clear_line(enemy.global_position + Vector3.UP * 0.8, samples[index] + Vector3.UP * 0.8):
					covered += 1
					samples.remove_at(index)
		enemy.face_direction(search.facing_direction(direction), delta)
		enemy.move_character(direction, delta, search.search_move_speed_multiplier)
	Engine.time_scale = previous_scale
	var ratio := float(covered) / maxi(1, sample_count)
	check(sample_count > 30 and visited > 1, "区域搜索验证包含实际导航与独立地面采样")
	check(ratio >= 0.9, "绕原地图墙体搜寻后，独立无遮挡覆盖超过90%")
	check(completed_round and next_round_started and ai.state == ai.State.SEARCH and ai.is_alerted,
		"没有新线索时完成一轮后继续下一轮搜索，保持交战警戒")
	check(peak_usec < 20000, "加入遮挡复核后搜索单步仍低于20毫秒")
	print("[SearchArea] samples=", sample_count, " observed=", ratio, " visits=", visited, " peak_usec=", peak_usec)
	search.search_radius = previous_radius

func _check_live_search(enemy, ai, player, random_seed: int, melee: bool = false) -> void:
	seed(random_seed)
	enemy.reset_target()
	Fixture.configure_timing(enemy)
	ai.training.profile.selected_tactics.clear()
	ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	ai.training.profile.set_setting(&"search", &"lost_target_hint_chance", 0.0)
	ai.training.profile.set_setting(&"search", &"search_hint_chance", 0.0)
	ai.training.profile.set_setting(&"search", &"debug_tracking_cheat", false)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	if melee:
		enemy.get_node("UnitType").profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.refresh_configuration(true)
	if melee:
		enemy.equip_weapon(preload("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	var melee_hits: Array[int] = [0]
	var on_melee_hit := func(target, _settings, _direction):
		if target == player: melee_hits[0] += 1
	enemy.melee_struck.connect(on_melee_hit)
	ai.set_physics_process(false)
	enemy.global_position = Vector3(20, 0, 2)
	player.global_position = Vector3(18, 0, 5.4)
	enemy.look_at(player.global_position)
	for frame in range(5): await physics_frame
	var saw := false
	var lost := false
	var investigated := false
	var recovered := false
	var fired := false
	var loss_position := Vector3.ZERO
	var progress := 0.0
	var shots_at_recovery := 0
	var maximum_usec := 0
	var last_action := ""
	for frame in range(1500):
		await physics_frame
		# 连续绕过原地图 CoverA 的南端，随后在墙背面静止。
		if frame >= 30 and frame < 66:
			player.global_position.x = lerpf(18.0, 15.0, float(frame - 29) / 36.0)
		elif frame >= 66 and frame < 102:
			player.global_position.z = lerpf(5.4, 2.4, float(frame - 65) / 36.0)
		var started := Time.get_ticks_usec()
		ai._physics_process(1.0 / 60.0)
		maximum_usec = maxi(maximum_usec, Time.get_ticks_usec() - started)
		saw = saw or ai.was_seeing_player
		if saw and not ai.was_seeing_player:
			if not lost: loss_position = enemy.global_position
			lost = true
			investigated = investigated or ai.utility_current.get("id") == &"search"
			progress = maxf(progress, enemy.global_position.distance_to(loss_position))
		elif lost:
			if not recovered: shots_at_recovery = melee_hits[0] if melee else enemy.shot_count
			recovered = true
			fired = (melee_hits[0] if melee else enemy.shot_count) > shots_at_recovery
		var action := str(ai.utility_current.get("id"), "/", ai.state, "/", ai.was_seeing_player)
		if action != last_action:
			print("[SearchLive] seed=", random_seed, " frame=", frame, " ", action, " at=", enemy.global_position)
			last_action = action
		if frame >= 102 and recovered and fired: break
	var label := "近战兵" if melee else "远程兵"
	check(saw and lost, "%s真实目击后连续绕墙造成失视 seed=%d" % [label, random_seed])
	check(investigated and progress > 0.5, "%s零提示且无声音时自主选中搜索并实际推进 seed=%d" % [label, random_seed])
	check(recovered and fired, "%s绕墙重新目击后实际开火或近战命中 seed=%d" % [label, random_seed])
	check(maximum_usec < 20000, "%s搜索与决策单帧保持原20毫秒门槛 seed=%d" % [label, random_seed])
	print("[SearchLive] peak_usec=", maximum_usec, " moved=", progress)
	enemy.melee_struck.disconnect(on_melee_hit)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
