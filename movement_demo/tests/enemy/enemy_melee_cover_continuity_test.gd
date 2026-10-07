extends SceneTree

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
	player.health.debug_invincible = false
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = load("res://resources/enemy/training/arena.tres").duplicate(true)
	ai.training.profile.action_overrides.append(load("res://scripts/enemy/config/melee_tactics_settings.gd").new())
	ai.training.profile.selected_tactics.assign([&"melee_cover"])
	ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	ai.cover_selection.debug_cover_selection = false
	await _check_case(enemy, ai, player, false)
	await _check_case(enemy, ai, player, true)
	print("COVER CONTINUITY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _check_case(enemy, ai, player, leave: bool) -> void:
	seed(20261007)
	enemy.reset_target()
	# 先自主选择正常推进；真实进入遮挡后现场调低本实例的绕出速度。
	# 检查设置确实生效并跨越原五秒期限，不强选动作或改写失视计时。
	ai.training.profile.set_setting(&"melee_tactics", &"cover_exit_speed_multiplier", 2.0)
	enemy.global_position = Vector3(28, 0, 1)
	player.global_position = Vector3(24, 0, -2.5)
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	enemy.receive_hit(5.0, player.global_position)
	var gun := WeaponData.new()
	gun.reload_seconds = 4.0
	player.combat.equip_weapon(gun)
	player.combat.ammo.infinite_reserve = true
	player.combat.ammo.magazine_rounds = 0
	player.combat.request_reload()
	for frame in 12:
		await physics_frame
		ai.context.update_evidence(1.0 / 60.0, ai.perception.can_see_player())
	var action = ai.actions[&"melee_cover"]
	var saw_target := false
	var entered_exit := false
	var crossed_memory_limit := false
	var premature_search := false
	var reacquired := false
	var old_evidence_rejected := false
	var peak_usec := 0
	var health: float = player.health.health
	var previous := ""
	var departed := false
	var search_returned := false
	var remembered := Vector3.INF
	var finish_deadline := INF
	var evidence_preserved := true
	var slowed := false
	for frame in 1100:
		await physics_frame
		var was_exiting: bool = ai.current_action == action and action.transfer.phase == action.transfer.Phase.PEEK_OUT
		var timer: float = action.transfer.timer
		ai._physics_process(1.0 / 60.0)
		if not slowed and ai.current_action == action and action.transfer.phase == action.transfer.Phase.RUN_TO_COVER and not ai.context.sees_player:
			ai.training.profile.set_setting(&"melee_tactics", &"cover_exit_speed_multiplier", 0.1)
			slowed = is_equal_approx(action._exit_speed(), 0.1)
		var state := str(ai.utility_current.get("id"), "/", action.transfer.phase, "/", ai.context.sees_player)
		if state != previous:
			print("CONTINUITY leave=", leave, " frame=", frame, " state=", state, " unseen=", ai.context.utility_unseen_seconds, " timer=", timer, " position=", enemy.global_position)
			previous = state
		saw_target = saw_target or ai.context.sees_player
		if was_exiting or ai.current_action == action:
			peak_usec = maxi(peak_usec, ai.frame_costs.decision + ai.frame_costs.execution)
		if ai.current_action == action and action.transfer.phase == action.transfer.Phase.PEEK_OUT and not ai.context.sees_player:
			entered_exit = true
		if entered_exit and ai.context.sees_player: reacquired = true
		if entered_exit and not reacquired:
			premature_search = premature_search or (not departed and ai.utility_current.get("id") == &"search")
			if ai.context.utility_unseen_seconds > float(ai.context.setting(&"melee_tactics", &"cover_memory_seconds", 5.0)):
				if was_exiting and timer > 0.0: crossed_memory_limit = true
				if ai.current_action == action:
					var candidates: Array = action.collect_candidates(false)
					old_evidence_rejected = not candidates.is_empty() and candidates.all(func(candidate): return ai.action_selector.same_option(candidate, ai.utility_current) and not action.validate(candidate, false))
					if leave and not departed:
						remembered = ai.context.last_known_position
						finish_deadline = ai.context.evidence_elapsed_seconds + action.transfer.timer + action.transfer.watch_seconds + 0.1
						player.global_position = Vector3(12, 0, 8)
						departed = true
		if departed:
			evidence_preserved = evidence_preserved and ai.context.last_known_position == remembered and not ai.context.sees_player
			if ai.utility_current.get("id") == &"search":
				search_returned = ai.context.evidence_elapsed_seconds <= finish_deadline
				break
		if premature_search or player.health.health < health: break
	check(saw_target and entered_exit, "真实目击、受压后自主选择掩体并进入绕出，不强选动作")
	check(slowed and crossed_memory_limit, "训练慢速设置实际生效，真实绕出路线跨越原五秒失视期限")
	check(not premature_search, "正在推进的绕出路线不因目击刚过期提前切为调查搜索")
	check(old_evidence_rejected, "过期证据只保留当前绕出候选，不能启动新的掩体推进")
	if leave:
		check(departed and search_returned and evidence_preserved and enemy.melee_count == 0 and player.health.health == health, "玩家真正离开后按原路线与观察时限返回搜索，不更新隐藏位置或攻击")
	else:
		check(reacquired and enemy.melee_count > 0 and player.health.health < health, "绕出后重新目击、自主接续近战并实际扣血")
	check(peak_usec < 20000, "掩体连续接敌决策与执行保留20毫秒门槛")
	print("CONTINUITY leave=", leave, " peak_usec=", peak_usec)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
