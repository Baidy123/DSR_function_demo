extends SceneTree

var checks := 0
var failures := 0

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
	player.get_node("Health").debug_invincible = true
	# 保留当前场景的武器、Training和Utility权重，玩家只沿墙端外侧移动。
	enemy.global_position = Vector3(24,0,-2)
	player.global_position = Vector3(24,0,2)
	enemy.look_at(player.global_position)
	for f in range(10): await physics_frame
	var seen := false
	var lost := false
	var investigated := false
	var recovered := false
	var hidden_cover := 0.0
	var longest_hidden_cover := 0.0
	var loss_position := Vector3.INF
	var hidden_movement := 0.0
	var last_action := ""
	var shots_at_recovery := -1
	var recovered_frame := -1
	var recovery_seconds := INF
	for f in range(1200):
		await physics_frame
		if f >= 120 and f < 180:
			player.global_position += Vector3(2.0,0,-0.5) / 60.0
		elif f >= 180 and f < 255:
			player.global_position.z += 2.5 / 75.0
		ai._physics_process(1.0 / 60.0)
		seen = seen or ai.was_seeing_player
		if seen and not ai.was_seeing_player and f >= 180:
			if not lost: loss_position = enemy.global_position
			lost = true
			investigated = investigated or ai.utility_current.get("id") == &"search"
			hidden_movement = maxf(hidden_movement, enemy.global_position.distance_to(loss_position))
			if ai.utility_current.get("id") == &"cover" and ai.utility_current.get("mode") != &"peek" and not enemy.ammo.is_reloading:
				hidden_cover += 1.0 / 60.0
			else: hidden_cover = 0.0
			longest_hidden_cover = maxf(longest_hidden_cover, hidden_cover)
		elif lost:
			if not recovered:
				shots_at_recovery = enemy.shot_count
				recovered_frame = f
			recovered = true
			hidden_cover = 0.0
		var action := str(ai.utility_current.get("id"), "/", ai.utility_current.get("mode", ""), "/visible=",ai.was_seeing_player)
		if action != last_action:
			print("CONTACT ",f," ",action," position=",enemy.global_position)
			last_action = action
		if recovered and enemy.shot_count > shots_at_recovery:
			recovery_seconds = float(f - recovered_frame) / 60.0
			break
		if "--capture" in OS.get_cmdline_user_args() and f in [300,420,600]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://logs/contact-visible-%d.png" % f)
	check(seen and lost, "真实交战后玩家绕入掩体造成失视")
	check(investigated and hidden_movement > 1.0, "无伤无来弹时实际架枪推进调查")
	check(longest_hidden_cover < 1.0, "失视本身不导致连续躲藏一秒以上")
	check(recovered, "绕墙调查后能重新发现玩家")
	check(shots_at_recovery >= 0 and enemy.shot_count > shots_at_recovery and recovery_seconds < 8.0, "重新目击后实际恢复射击，不在墙端反复退回")
	print("CONTACT longest hidden cover=",longest_hidden_cover," recovered fire seconds=",recovery_seconds)
	# 在同一几何和记忆下比较，失视首帧也必须计算未来躲藏的信息损失。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = enemy.weapon.magazine_capacity
	enemy.global_position = Vector3(22,0,2)
	player.global_position = Vector3(26,0,4)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = Vector3(26,0,1)
	ai.last_seen_position = ai.last_known_position
	ai.utility_unseen_seconds = 0.01
	ai.utility_threat_age_seconds = 0.01
	ai.recent_damage_pressure = 0.0
	ai.nearby_shot_pressure = 0.0
	for f in range(60):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai,false)
	var options: Array = ai.action_selector.assess_options(ai,false)
	# 有限起身观察／射击是新方案，不能当作整个窗口都不观察的纯躲藏。
	var covers: Array = options.filter(func(o):return o.id == &"cover" and o.get("mode") not in [&"peek", &"low_cover_burst"])
	check(not covers.is_empty(), "失视仍保留Training允许的躲藏候选")
	check(not covers.is_empty() and covers.all(func(o):return o.breakdown.information_loss >= ai.utility_horizon_seconds), "躲藏按未来观察窗失去信息计分")
	var search: Dictionary = options.filter(func(o):return o.id == &"search")[0]
	check(is_zero_approx(search.breakdown.risk_cost), "健康无受压时不把旧位置算作正在开火的敌人")
	var without_bursts: Array = options.filter(func(o): return o.get("mode") != &"low_cover_burst")
	check(ai.action_selector.choose_option(without_bursts).id == &"search", "刚失视时调查仍胜过整窗纯躲藏")
	var bursts: Array = options.filter(func(o): return o.id == &"cover" and o.get("mode") == &"low_cover_burst")
	var observation := {}
	for candidate in bursts:
		var origin: Vector3 = enemy.get_posture_muzzle_position(false, candidate.destination.hide)
		var target: Vector3 = enemy.get_posture_eye_position(false, ai.last_known_position)
		if candidate.breakdown.information_loss < ai.utility_horizon_seconds and candidate.breakdown.unavailable_seconds < ai.utility_horizon_seconds and ai.cover_selection.has_clear_line(origin, target) and ai.context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
			observation = candidate
			break
	check(not observation.is_empty(), "有限起身方案以实际可观察枪线获得信息和火力收益")
	var chosen: Dictionary = ai.action_selector.choose_option(options)
	check(chosen.id == &"search" or (chosen.id == &"cover" and chosen.get("mode") == &"low_cover_burst" and chosen.breakdown.information_loss < ai.utility_horizon_seconds), "新鲜失视由调查或有限起身观察胜出，不由纯躲藏抢占")
	# 使用真实受击入口积累压力，不能用超过生产上限的合成值。
	enemy.receive_hit(1.0)
	enemy.receive_hit(1.0)
	enemy.receive_hit(1.0)
	var pressured: Array = ai.action_selector.assess_options(ai,false)
	check(ai.action_selector.choose_option(pressured).id == &"cover", "相同几何下实际受压仍能选择躲藏")
	ai.recent_damage_pressure = 0.0
	enemy.health = enemy.max_health * 0.1
	var wounded: Dictionary = ai.action_selector.assess_options(ai,false).filter(func(o):return o.id == &"search")[0]
	check(wounded.breakdown.risk_cost > search.breakdown.risk_cost, "低血量仍提高调查路线风险")
	enemy.health = enemy.max_health
	enemy.ammo.magazine_rounds = 0
	ai.invalidate_utility()
	ai._update_utility_decision(0.5,false)
	check(enemy.ammo.is_reloading, "当前3.5秒武器空匣失视时仍实际启动换弹")
	for f in range(240):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	check(enemy.ammo.magazine_rounds > 0 and not enemy.ammo.is_reloading, "失视换弹能完成，不被搜索不断重启")
	if not observation.is_empty():
		await _check_finite_observation(ai, enemy, player, observation)
	print("LOST CONTACT INITIATIVE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)

func _check_finite_observation(ai, enemy, player, candidate: Dictionary) -> void:
	# 自主完整一轮实弹与蹲回由 enemy_low_cover_behavior_test 覆盖。
	# 此处专验本次失视候选：真实到位后起身仍没看到目标，必须有限退出且不能凭记忆开火。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = enemy.weapon.magazine_capacity
	enemy.global_position = candidate.destination.hide
	enemy.velocity = Vector3.ZERO
	player.global_position = Vector3(15, 0, 2)
	ai.context.last_known_position = Vector3(26, 0, 1)
	ai.context.last_seen_position = ai.context.last_known_position
	ai.context.has_visual_memory = true
	ai.context.is_alerted = true
	ai.context.sees_player = false
	ai.context.was_seeing_player = false
	ai.context.utility_unseen_seconds = 0.01
	enemy.request_crouch(true)
	for frame in ceili(enemy.posture_seconds * 60.0) + 2: await physics_frame
	check(not ai.perception.can_see_player(), "有限观察执行用例的真实玩家仍被另一面墙遮挡")
	ai._start_utility_option(candidate, false)
	var cover = ai.actions[&"cover"]
	var rose := false
	var shots: int = enemy.shot_count
	var hidden := true
	for frame in 240:
		await physics_frame
		var visible: bool = ai.perception.can_see_player()
		hidden = hidden and not visible
		ai.context.update_evidence(1.0 / 60.0, visible)
		var output: Dictionary = cover.execute_tick(1.0 / 60.0, visible)
		enemy.request_crouch(output.get("crouch", false))
		enemy.face_direction(output.get("facing", Vector3.ZERO), 1.0 / 60.0)
		enemy.move_character(output.direction, 1.0 / 60.0, output.multiplier)
		ai.context.fire.update(1.0 / 60.0, visible, false, output.fire)
		rose = rose or enemy.body_motion.amount <= 0.0001
		if rose and not cover.low_cycle.active(): break
	check(hidden and enemy.shot_count == shots, "有限观察没有重新目击就不会凭隐藏位置或旧记忆开火")
	check(rose and enemy.is_crouching() and not cover.low_cycle.active() and not cover.valid(false), "有限失视观察实际起身后蹲回并释放执行，不无限占住调查")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
