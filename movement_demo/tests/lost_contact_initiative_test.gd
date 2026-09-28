extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(82)
	var scene = load("res://main.tscn").instantiate()
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
	for f in range(780):
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
			if not recovered: shots_at_recovery = enemy.shot_count
			recovered = true
			hidden_cover = 0.0
		var action := str(ai.utility_current.get("id"), "/", ai.utility_current.get("mode", ""), "/visible=",ai.was_seeing_player)
		if action != last_action:
			print("CONTACT ",f," ",action," position=",enemy.global_position)
			last_action = action
		if "--capture" in OS.get_cmdline_user_args() and f in [300,420,600]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://logs/contact-visible-%d.png" % f)
	check(seen and lost, "真实交战后玩家绕入掩体造成失视")
	check(investigated and hidden_movement > 1.0, "无伤无来弹时实际架枪推进调查")
	check(longest_hidden_cover < 1.0, "失视本身不导致连续躲藏一秒以上")
	check(recovered, "绕墙调查后能重新发现玩家")
	check(shots_at_recovery >= 0 and enemy.shot_count > shots_at_recovery, "重新目击后实际恢复射击，不在墙端反复退回")
	print("CONTACT longest hidden cover=",longest_hidden_cover)
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
		ai.action_selector.advance_evaluation(ai,false)
	var options: Array = ai.action_selector.assess_options(ai,false)
	var covers: Array = options.filter(func(o):return o.id == &"cover" and o.get("mode") != &"peek")
	check(not covers.is_empty(), "失视仍保留Training允许的躲藏候选")
	check(not covers.is_empty() and covers.all(func(o):return o.breakdown.information_loss >= ai.utility_horizon_seconds), "躲藏按未来观察窗失去信息计分")
	var search: Dictionary = options.filter(func(o):return o.id == &"search")[0]
	check(is_zero_approx(search.breakdown.risk_cost), "健康无受压时不把旧位置算作正在开火的敌人")
	check(ai.action_selector.choose_option(options).id == &"search", "刚失视也能选择调查而非先退避")
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
	print("LOST CONTACT INITIATIVE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
