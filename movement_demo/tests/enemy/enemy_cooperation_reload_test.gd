extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
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
		ai.training.profile.set_setting(&"tactics", &"fire_reaction_seconds", 0.0)
		ai.training.profile.set_setting(&"tactics", &"burst_shot_count", 12)
		ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 0.0)
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.refresh_configuration(true)
		actor.weapon.magazine_capacity = 40
		actor.ammo.magazine_rounds = 40
		actor.weapon.reload_seconds = 1.2
		actor.weapon.shot_interval = 0.8
		actor.debug_shooting = false
		actor.aim_turn_speed_degrees = 720.0
		ai.cover_selection.debug_cover_selection = false
		ai.cover_selection.debug_attack_points = false
	first.global_position = Vector3(18, 0, 0)
	player.global_position = Vector3(23, 0, 1)
	first.look_at(player.global_position)
	second.look_at(player.global_position)
	for frame in 10: await physics_frame
	# 先由真实接敌、瞄准与枪线建立支援，不往协作板伪填 ready。
	for frame in 20:
		await physics_frame
		first_ai._physics_process(STEP)
		second_ai._physics_process(STEP)
	var reload_action = first_ai.actions[&"reload"]
	first.ammo.magazine_rounds = 40
	check(reload_action.collect_candidates(true).is_empty(), "满弹匣不生成协调补弹候选")
	first.ammo.magazine_rounds = 14
	var candidates: Array = reload_action.collect_candidates(true)
	check(candidates.any(func(candidate): return candidate.get("proactive_reload", false) and not candidate.get("urgent", true)), "低余弹且队友实际就绪时提供非紧急的主动补弹方案")
	var precise := true
	for candidate: Dictionary in candidates:
		if not candidate.get("proactive_reload", false): continue
		precise = precise and candidate.outcome.unavailable_seconds >= first.weapon.reload_seconds - 0.001 and candidate.outcome.cooperation_seconds <= first.weapon.reload_seconds + 0.001
	check(precise and not candidates.is_empty(), "余弹换弹估计包含真实完整耗时，合作收益不超过实际支持窗口")
	var before: int = first_ai.context.cooperation_snapshot().claims.size()
	reload_action.collect_candidates(true)
	reload_action.collect_candidates(true)
	check(before == first_ai.context.cooperation_snapshot().claims.size(), "候选评估不提前抢占补弹名额")
	# 双方的余弹可覆盖一次换弹及恢复射界，允许正常 Utility 自主错开补弹。
	second.ammo.magazine_rounds = 14
	var started := [false, false]
	var filled := [false, false]
	var overlap := false
	var spent_ammo_during_reload := false
	var previous_rounds := [14, 14]
	var both_ready_again := false
	var trace: Array = []
	for frame in 900:
		await physics_frame
		first_ai._physics_process(STEP)
		second_ai._physics_process(STEP)
		if frame % 30 == 0:
			var row: Array = [frame]
			for ai in [first_ai, second_ai]:
				var choices: Array = []
				for candidate: Dictionary in ai.utility_options:
					if candidate.id == &"reload": choices.append({"plan": candidate.plan, "cost": candidate.cost, "outcome": candidate.outcome})
				row.append({"action": ai.utility_current.get("id"), "plan": ai.utility_current.get("plan"), "cost": ai.utility_current.get("cost"), "rounds": ai.actor.ammo.magazine_rounds, "reloading": ai.actor.ammo.is_reloading, "fire_decision": ai.context.fire.fire_decision.selected_action, "opportunity": ai.context.cooperation_reload_opportunity(), "reload_choices": choices})
			trace.append(row)
		var actors: Array = [first, second]
		for index in 2:
			var actor = actors[index]
			if actor.ammo.is_reloading:
				started[index] = started[index] or actor.ammo.magazine_rounds > 0
				spent_ammo_during_reload = spent_ammo_during_reload or actor.ammo.magazine_rounds < previous_rounds[index]
			if started[index] and actor.ammo.magazine_rounds >= actor.weapon.magazine_capacity - 2: filled[index] = true
			previous_rounds[index] = actor.ammo.magazine_rounds
		overlap = overlap or (first.ammo.is_reloading and second.ammo.is_reloading and first.ammo.magazine_rounds > 0 and second.ammo.magazine_rounds > 0)
		both_ready_again = both_ready_again or (filled[0] and filled[1] and not first.ammo.is_reloading and not second.ammo.is_reloading)
		if both_ready_again: break
	if not both_ready_again: print("[CooperationReload] ", JSON.stringify({"started": started, "filled": filled, "trace": trace}))
	check(started[0] and started[1], "两名敌人由正常 Utility 在弹匣打空前分别自主开始换弹")
	check(not overlap, "主动补弹认领阻止两人同时丢失火力")
	check(filled[0] and filled[1] and both_ready_again and not spent_ammo_during_reload, "实际换弹计时补满且恢复攻击，换弹中不消耗余弹")
	await _check_short_window(first, second, player, 7)
	await _check_short_window(first, second, player, 3)
	await _check_after_cover(first, second, player)
	# 支持中断后，不凭上一轮 ready 快照继续制造主动机会。
	first_ai.reset_actions()
	first.cancel_reload()
	first.ammo.magazine_rounds = 3
	second.shooting_enabled = false
	await physics_frame
	second_ai._physics_process(STEP)
	candidates = reload_action.collect_candidates(true)
	check(not candidates.any(func(candidate): return candidate.get("proactive_reload", false)), "队友失去实际射击资格后不盲目选主动补弹")
	Fixture.set_training_action(first_ai, &"cooperate", false)
	check(reload_action.collect_candidates(true).is_empty(), "撤销合作训练后余弹恢复原个人行为，不保留主动补弹资格")
	Fixture.set_training_action(first_ai, &"cooperate", true)
	# 紧急空匣不受主动名额或支援状态阻止。
	first.ammo.magazine_rounds = 0
	second.ammo.magazine_rounds = 0
	var urgent: Array = reload_action.collect_candidates(true)
	check(not urgent.is_empty() and urgent.all(func(candidate): return candidate.get("urgent", false) and not candidate.get("proactive_reload", false)), "空匣换弹保持独立紧急候选，即使无人能够支援")
	for frame in 5:
		await physics_frame
		first_ai._physics_process(STEP)
	check(first.ammo.is_reloading, "无人支援的空匣敌人仍由原决策实际开始换弹")
	print("ENEMY COOPERATION RELOAD: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _check_short_window(first, second, player, rounds: int) -> void:
	var first_ai = first.get_node("AI")
	var second_ai = second.get_node("AI")
	for actor in [first, second]:
		actor.reset_target()
	first.global_position = Vector3(18, 0, 0)
	second.global_position = Vector3(18, 0, 2)
	player.global_position = Vector3(23, 0, 1)
	for actor in [first, second]: actor.look_at(player.global_position)
	for frame in 3: await physics_frame
	first.ammo.magazine_rounds = rounds
	second.ammo.magazine_rounds = rounds
	var proactive := false
	var empty_seen := false
	var urgent_started := false
	var urgent_available := true
	for frame in 480 if rounds == 7 else 240:
		await physics_frame
		first_ai._physics_process(STEP)
		second_ai._physics_process(STEP)
		for actor in [first, second]:
			proactive = proactive or (actor.ammo.is_reloading and actor.ammo.magazine_rounds > 0)
			if actor.ammo.magazine_rounds == 0:
				empty_seen = true
				urgent_started = urgent_started or actor.ammo.is_reloading
				var options: Array = actor.get_node("AI").actions[&"reload"].collect_candidates(true)
				urgent_available = urgent_available and options.any(func(candidate): return candidate.get("urgent", false))
	check(proactive, "%d发短支持窗口仍能自主利用一次余弹补弹机会" % rounds)
	check(urgent_available and (not empty_seen or urgent_started), "%d发窗口不能保证双方都提前补弹，但实际临空后紧急补弹不会被主动排班禁止" % rounds)

func _check_after_cover(first, second, player) -> void:
	# 这一段单独验证已选择方案的执行协议；自主选择已由上面的真实双人循环验证。
	var ai = first.get_node("AI")
	var other_ai = second.get_node("AI")
	for actor in [first, second]:
		actor.get_node("AI").reset_actions()
		actor.cancel_reload()
		actor.ammo.magazine_rounds = 20
	Fixture.set_training_action(ai, &"cover", true)
	first.global_position = Vector3(24, 0, -2)
	second.global_position = Vector3(24, 0, -4)
	player.global_position = Vector3(20, 0, -2)
	for actor in [first, second]: actor.look_at(player.global_position)
	first.ammo.magazine_rounds = 3
	var action = ai.actions[&"reload"]
	var selected: Dictionary = {}
	for frame in 120:
		await physics_frame
		ai.context.update_evidence(STEP, ai.perception.can_see_player())
		ai.context.spatial.advance_evaluation()
		other_ai._physics_process(STEP)
		for candidate: Dictionary in action.collect_candidates(ai.context.sees_player):
			if candidate.get("plan") != &"proactive_after_cover" or candidate.destination.is_empty(): continue
			if selected.is_empty() or float(candidate.outcome.unavailable_seconds) < float(selected.outcome.unavailable_seconds): selected = candidate
		if not selected.is_empty(): break
	check(not selected.is_empty(), "真实地图和现有预算提供合法的先到掩体再主动补弹方案")
	if selected.is_empty(): return
	ai._start_utility_option(selected, ai.context.sees_player)
	check(action._running and not first.ammo.is_reloading and first.ammo.magazine_rounds == 3, "余弹先躲后换的途中阶段不提前开始或误报换弹完成")
	var actually_started := false
	var complete := false
	var stayed_loaded := true
	for frame in 600:
		await physics_frame
		other_ai._physics_process(STEP)
		ai.context.update_evidence(STEP, ai.perception.can_see_player())
		var output: Dictionary = action.tick(STEP, ai.context.sees_player)
		first.move_character(output.direction, STEP, output.multiplier)
		ai.context.fire.update(STEP, ai.context.sees_player, not output.direction.is_zero_approx(), output.fire)
		ai.context.cooperation_publish_execution(output)
		actually_started = actually_started or first.ammo.is_reloading
		if not actually_started: stayed_loaded = stayed_loaded and first.ammo.magazine_rounds == 3
		complete = first.ammo.magazine_rounds == first.weapon.magazine_capacity and not first.ammo.is_reloading
		if complete or not action._running: break
	check(actually_started and complete and stayed_loaded, "实际抵达掩体后即使仍有余弹也开始换弹，并按原身体计时补满")
	ai.reset_actions()
	Fixture.set_training_action(ai, &"cover", false)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
