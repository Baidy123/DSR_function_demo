extends "res://tests/enemy/enemy_wave_test.gd"

## 复用原波次夹具和真实区域推进；墙体遮挡玩家，不注入状态、任务或获选动作。
func _run() -> void:
	root.get_node("DebugSettings").enabled = false
	if "--saved-lvl5" in OS.get_cmdline_user_args():
		await _saved_lvl5_search_case()
		print("WAVE SPAWN SEARCH LVL5: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	seed(20261026)
	_configuration()
	for level in 3: await _spawn_search_case(level)
	await _disabled_case()
	await _no_fast_case()
	await _reordered_case()
	await _blocked_spawn_case()
	print("WAVE SPAWN SEARCH: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _configuration() -> void:
	var wave := Wave.new()
	check(wave.search_on_spawn and is_equal_approx(wave.spawn_search_error_radius, 3.0), "后续波默认开启出生搜索，默认误差3米")
	wave.spawn_search_error_radius = -1.0
	check("出生搜索" in "".join(wave.deployment_configuration().errors), "负误差半径给出中文配置诊断")
	wave.spawn_search_error_radius = NAN
	check("出生搜索" in "".join(wave.deployment_configuration().errors), "非有限误差半径给出配置诊断")
	wave.free()

func _hidden_fixture(level: int, enabled: bool = true) -> Node3D:
	var region := _fixture()
	var controller = region.get_node("EnemyWaves")
	var later = controller.get_node("Wave2")
	later.wait_for_previous_clear = false
	later.start_delay_seconds = 0.35
	later.search_on_spawn = enabled
	later.spawn_search_error_radius = 2.0
	var extra = SquadScene.instantiate()
	extra.name = "OtherSquad"
	later.add_child(extra)
	var ranged = load("res://scenes/enemy/levels/lvl_2/pistol.tscn").instantiate()
	ranged.name = "Ranged"
	ranged.position = Vector3(5, 0, 3)
	ranged.get_node("NavigationAgent3D").path_height_offset = 0.0
	# 明确本用例的射击输入：保存的手枪资源可能被用户调成近战，不覆盖原资源。
	ranged.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	ranged.weapon = WeaponData.new()
	ranged.weapon.magazine_capacity = 6
	ranged.weapon.fire_range = 30.0
	extra.add_child(ranged)
	for wave in controller.get_children():
		for squad in wave.get_children():
			squad.profile = squad.profile.duplicate(true)
			squad.profile.level = level
			for enemy in squad.get_children():
				enemy.move_speed = 2.0
				var training = enemy.get_node("Training")
				training.profile = training.profile.duplicate(true)
				training.profile.selected_tactics.clear()
				training.profile.search.tracking_cheat_enabled = false
				# 普通未目击调查会在这个时间后结束；出生搜索应持续警戒。
				training.profile.search.search_seconds = 0.1
				training.profile.search.combat_pursuit_seconds = 1.5
				training.profile.search.combat_pursuit_speed_multiplier = 1.8
				training.profile.search.focused_search_seconds = 2.5
				training.profile.search.focused_search_speed_multiplier = 1.0
	var wall := StaticBody3D.new()
	wall.name = "SightWall"
	wall.position = Vector3(0, 2, 6)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(26, 4, 0.4)
	wall.add_child(shape)
	region.add_child(wall)
	region.get_node("Player").position = Vector3(0, 0, 8)
	controller.wave_started.connect(func(index):
		if index == 1:
			# 首波保持原地，排除前波巡逻占位；后波继续真实 AI 和身体更新。
			for enemy in region.enemies:
				enemy.set_physics_process(false)
				enemy.get_node("AI").set_physics_process(false))
	return region

func _spawn_search_case(level: int) -> void:
	var region := _hidden_fixture(level)
	var controller = region.get_node("EnemyWaves")
	root.add_child(region)
	current_scene = region
	var player = region.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	check(await _await_wave(controller, 1), "等级%d：首波按原流程生成" % level)
	var original: Array = region.enemies.duplicate()
	check(original.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint.is_empty() and not enemy.get_node("AI").context.is_alerted), "等级%d：首波即使开关默认开启也不注入出生警戒" % level)
	player.global_position.x = 4.0
	var expected_capture: Vector3 = player.global_position
	check(await _await_wave(controller, 2), "等级%d：后波按实际加入时间生成" % level)
	var members: Array = region.enemies.filter(func(enemy): return not original.has(enemy))
	check(members.size() == 3, "等级%d：后波两个小队完整出场" % level)
	check(members.any(func(enemy): return enemy.can_use_firearms() and enemy.ammo.magazine_rounds > 0), "等级%d：墙后禁射检查包含实际装备枪械且有弹药的成员" % level)
	if members.is_empty():
		region.queue_free()
		await _settle()
		return
	var first_hint: Dictionary = members[0].get_node("AI").context.spawn_search_hint.duplicate(true)
	check(not first_hint.is_empty() and first_hint.source == &"wave_spawn" and Vector2(first_hint.position.x - expected_capture.x, first_hint.position.z - expected_capture.z).length() <= 2.001, "等级%d：提示来自实际出生时快照且误差在配置半径内" % level)
	check(members.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint == first_hint), "等级%d：同波不同小队共用一份情报，人数不增加采样" % level)
	var starts := {}
	for enemy in members: starts[enemy.get_instance_id()] = enemy.global_position
	player.global_position.x = -6.0
	var patrolled := false
	var sight_or_fire := false
	var searched := false
	var fast_phase := false
	var source_clock_preserved := true
	var peak_speed_ratio := 0.0
	var previous := starts.duplicate()
	var previous_frame := Engine.get_physics_frames()
	for frame in 120:
		await _settle(1)
		var current_frame := Engine.get_physics_frames()
		var sample_seconds := float(current_frame - previous_frame) / float(Engine.physics_ticks_per_second)
		for enemy in members:
			var ai = enemy.get_node("AI")
			var before: Vector3 = previous[enemy.get_instance_id()]
			var after: Vector3 = enemy.global_position
			if sample_seconds > 0.0: peak_speed_ratio = maxf(peak_speed_ratio, Vector2(after.x - before.x, after.z - before.z).length() / sample_seconds / enemy.move_speed)
			previous[enemy.get_instance_id()] = after
			patrolled = patrolled or ai.context.state == ai.State.PATROL
			sight_or_fire = sight_or_fire or ai.context.has_visual_memory or ai.context.sees_player or enemy.shot_count > 0
			if level == 0:
				source_clock_preserved = source_clock_preserved and absf(ai.actions[&"search"]._search_evidence_age() - (ai.context.coordination_now() - float(first_hint.captured_at))) < 0.001
				searched = searched or (ai.current_action != null and ai.current_action.action_id == &"search" and ai.context.state in [ai.State.TRACK, ai.State.SEARCH])
				fast_phase = fast_phase or (ai.current_action != null and ai.current_action.action_id == &"search" and ai.current_action.movement_multiplier() > 1.0)
			else:
				var objective: Dictionary = ai.context.coordination_debug_snapshot().get("objective", {})
				searched = searched or objective.get("phase") == &"search"
				var task: Dictionary = ai.context.coordination_assignment()
				patrolled = patrolled or task.get("role") == &"patrol"
				fast_phase = fast_phase or (task.get("role") == &"search" and float(task.get("pursuit_until", -INF)) > ai.context.coordination_now())
		previous_frame = current_frame
	check(searched and not patrolled, "等级%d：出生直接追查／搜索，不执行巡逻" % level)
	check(fast_phase and peak_speed_ratio > 1.15, "等级%d：已有快速阶段产生实际加速位移（峰值%.2f倍）" % [level, peak_speed_ratio])
	check(members.any(func(enemy): return enemy.global_position.distance_to(starts[enemy.get_instance_id()]) > 0.2), "等级%d：搜索产生实际身体移动" % level)
	check(not sight_or_fire and members.all(func(enemy): return not enemy.get_node("AI").context.last_seen_aim_position.is_finite()), "等级%d：实体墙后不伪造目击、瞄点或开火" % level)
	check(members.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint == first_hint and enemy.get_node("AI").context.is_alerted), "等级%d：隐蔽位移及普通调查超时不刷新提示或解除警戒" % level)
	check(original.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint.is_empty() and not enemy.get_node("AI").context.is_alerted), "等级%d：出生提示不广播给在场旧波次" % level)
	if level > 0:
		check(members.all(func(enemy): return enemy.get_node("AI").utility_decision_count == 0 and enemy.get_node("AI").context.commanded()), "等级%d：全程保留团队控制权，个人Utility次数为0" % level)
		check(members.all(func(enemy): return float(enemy.get_node("AI").context.coordination_assignment().get("pursuit_until", -INF)) <= float(first_hint.captured_at) + 1.501), "等级%d：重排和到点不返还出生快速时窗" % level)
	else:
		var ai = members[0].get_node("AI")
		var search = ai.actions[&"search"]
		check(source_clock_preserved, "出生快速阶段按原区域捕获时间计龄，不混用新成员的局部时钟")
		var old_age: float = search.search_elapsed_seconds
		search._end_search()
		check(ai.context.is_alerted and search.investigation_phase == ai.State.SEARCH and search.search_elapsed_seconds == old_age and not ai.context.has_visual_memory, "个人搜完一轮继续搜索，保持衰减年龄且不伪造战斗目击")
		check(not search._fresh_pursuit() and search.movement_multiplier() <= 1.0, "搜索换轮不刷新出生年龄，不重复获得快速追查")
	var elapsed: float = members[0].get_node("AI").context.evidence_elapsed_seconds
	paused = true
	await _settle(3)
	check(members[0].get_node("AI").context.evidence_elapsed_seconds == elapsed, "等级%d：暂停冻结出生搜索时钟" % level)
	paused = false
	player.is_in_dialogue = true
	await _settle(3)
	check(members.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint == first_hint), "等级%d：对话保留冻结提示" % level)
	player.is_in_dialogue = false
	await _settle(8)
	check(members.all(func(enemy): return enemy.get_node("AI").context.is_alerted and enemy.get_node("AI").context.state != enemy.get_node("AI").State.PATROL), "等级%d：对话结束继续搜索" % level)
	controller.reset_encounter()
	controller.start_encounter()
	check(await _await_wave(controller, 2), "等级%d：整轮复位后可再次生成后波" % level)
	var fresh_hint: Dictionary = controller.get_node("Wave2/Squad/Enemy/AI").context.spawn_search_hint
	check(not fresh_hint.is_empty() and fresh_hint.id != first_hint.id and fresh_hint.captured_at > first_hint.captured_at and Vector2(fresh_hint.position.x - player.global_position.x, fresh_hint.position.z - player.global_position.z).length() <= 2.001, "等级%d：新一轮重新取样，不重放旧提示" % level)
	if level == 0:
		region.get_node("SightWall").queue_free()
		player.global_position = Vector3(0, 0, 5)
		var reacquired := false
		for frame in 120:
			await _settle(1)
			var live = controller.get_node("Wave2/Squad/Enemy/AI")
			if live.context.has_visual_memory and live.current_action != null and live.current_action.action_id != &"search":
				reacquired = true
				break
		check(reacquired, "出生搜索后实际目击玩家，正常接敌流程接管")
	region.queue_free()
	await _settle()

func _saved_lvl5_search_case() -> void:
	seed(2)
	var region = load("res://scenes/world/levels/lvl_5.tscn").instantiate()
	root.add_child(region)
	current_scene = region
	region.get_node("LevelFlow/PlayGuide").close_guide()
	var player = region.get_node("Player")
	player.set_physics_process(false)
	# 内存实例中把玩家留在地图中央的合法空地，隔开出生区与玩家；不改保存场景。
	player.global_position = region.to_global(Vector3(0, 0, 3))
	player.get_node("Health").debug_invincible = true
	var controller = region.get_node("EnemyWaves")
	check(await _await_wave(controller, 1, 180), "第五关保存地图按原流程生成首波")
	for number in [2, 3]:
		for enemy in region.enemies.duplicate(): enemy.receive_hit(100000.0)
		var spawned: bool = await _await_wave(controller, number, 180)
		check(spawned and region.enemies.size() == 6, "第五关第%d波真实死亡清波后生成六人小队" % number)
		if not spawned: break
		var starts := {}
		var travelled := {}
		for enemy in region.enemies:
			starts[enemy.get_instance_id()] = enemy.global_position
			travelled[enemy.get_instance_id()] = 0.0
		check(region.enemies.all(func(enemy): return not enemy.get_node("AI").context.spawn_search_hint.is_empty()), "第五关第%d波全员取得出生搜索线索" % number)
		for frame in range(720):
			await physics_frame
			for enemy in region.enemies:
				var id: int = enemy.get_instance_id()
				travelled[id] = maxf(travelled[id], enemy.global_position.distance_to(starts[id]))
		var moved := travelled.values().filter(func(distance): return distance > 1.0).size()
		check(moved >= 2, "第五关第%d波至少两名成员实际离开出生点（本次%d/6）" % [number, moved])
		check(region.enemies.any(func(enemy): return enemy.global_position.distance_to(player.global_position) + 1.0 < starts[enemy.get_instance_id()].distance_to(player.global_position)), "第五关第%d波实际向玩家所在区域推进" % number)
		check(region.enemies.all(func(enemy): return enemy.get_node("AI").context.commanded() and enemy.get_node("AI").utility_decision_count == 0), "第五关第%d波保持原团队控制权" % number)
	region.queue_free()
	await _settle()

func _disabled_case() -> void:
	var region := _hidden_fixture(0, false)
	var controller = region.get_node("EnemyWaves")
	root.add_child(region)
	current_scene = region
	region.get_node("Player").set_physics_process(false)
	check(await _await_wave(controller, 2), "关闭出生搜索仍按原波次条件生成")
	await _settle(20)
	var members: Array = controller.get_node("Wave2/Squad").get_children()
	check(members.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint.is_empty() and not enemy.get_node("AI").context.is_alerted), "关闭开关后不注入情报或警戒，保留原出生行为")
	region.queue_free()
	await _settle()

func _no_fast_case() -> void:
	var region := _hidden_fixture(0)
	var controller = region.get_node("EnemyWaves")
	for squad in controller.get_node("Wave2").get_children():
		for enemy in squad.get_children(): enemy.get_node("Training").profile.search.combat_pursuit_seconds = 0.0
	root.add_child(region)
	current_scene = region
	region.get_node("Player").set_physics_process(false)
	check(await _await_wave(controller, 2), "快速时长为0仍正常生成出生搜索")
	var ai = controller.get_node("Wave2/Squad/Enemy/AI")
	await _settle(20)
	var search = ai.actions[&"search"]
	check(ai.context.is_alerted and not search._fresh_pursuit() and search.movement_multiplier() <= 1.0, "0秒关闭快速阶段，保留出生搜索与警戒")
	region.queue_free()
	await _settle()

func _blocked_spawn_case() -> void:
	var region := _hidden_fixture(0)
	var controller = region.get_node("EnemyWaves")
	controller.get_node("Wave2").spawn_search_error_radius = 0.0
	var blocker := CharacterBody3D.new()
	blocker.position = Vector3(-2, 0, 3)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 0.875
	blocker.add_child(shape)
	region.add_child(blocker)
	root.add_child(region)
	current_scene = region
	var player = region.get_node("Player")
	player.set_physics_process(false)
	check(await _await_state(controller, "BLOCKED"), "后波被实际身体占位时等待")
	check(controller._pending.all(func(deployment): return deployment.members.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint.is_empty())), "等待占位期间树外部署没有提前取得提示")
	# 提示按水平误差约束；角色临时抬升时，仍可投影到本区地面。
	player.global_position = Vector3(-4, 1.25, 8)
	blocker.queue_free()
	check(await _await_wave(controller, 2), "让开刷新点后整波正常出场")
	var ai = controller.get_node("Wave2/Squad/Enemy/AI")
	check(not ai.context.spawn_search_hint.is_empty() and ai.context.spawn_search_hint.position.is_equal_approx(Vector3(-4, 0, 8)), "0误差在让开后读取最新水平位置，临时抬升仍投影到本区导航")
	var captured: Dictionary = ai.context.spawn_search_hint.duplicate(true)
	check(not ai.receive_spawn_search_hint(captured), "同一轮重复交付不会重新开始搜索")
	player.global_position = Vector3(30, 0, 30)
	check(await _await_state(controller, "WAITING") and region.enemies.is_empty(), "离场清理出生搜索成员和本轮情报")
	region.queue_free()
	await _settle()

func _reordered_case() -> void:
	var region := _hidden_fixture(0)
	var controller = region.get_node("EnemyWaves")
	controller.move_child(controller.get_node("Wave2"), 0)
	controller.get_node("Wave1").wait_for_previous_clear = false
	controller.get_node("Wave1").start_delay_seconds = 0.15
	root.add_child(region)
	current_scene = region
	region.get_node("Player").set_physics_process(false)
	check(await _await_wave(controller, 1), "重排后仍按公开编号1报告实际首波")
	check(region.enemies.all(func(enemy): return enemy.get_node("AI").context.spawn_search_hint.is_empty()), "名为Wave2的波次移到首位后受第0波保护")
	check(await _await_wave(controller, 2), "原首波移到后面后按新顺序生成")
	check(controller.get_node("Wave1/Squad/Enemy/AI").context.spawn_search_hint.get("source") == &"wave_spawn", "名为Wave1的原首波移到后面后可正常出生搜索")
	region.queue_free()
	await _settle()
