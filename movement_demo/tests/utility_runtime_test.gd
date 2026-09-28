extends SceneTree

var failed := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy_fire_fixture.gd").configure_timing(enemy)
	for name in ["attack_position", "suppression", "exit_suppression"]:
		var action = load("res://enemy_actions/" + name + ".tres")
		ai.unit_type.available_actions.append(action)
		ai.training.allowed_actions.append(action)
	ai.tactics.can_use_attack_positions = true
	ai.tactics.can_suppress_fire = true
	ai.cover_selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	player.get_node("Health").debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	enemy.look_at(player.global_position)
	enemy.weapon.magazine_capacity = 3
	enemy.ammo.magazine_rounds = 3
	for frame in range(5): await physics_frame
	var samples: Array[int] = []
	var actions := {}
	var saw_reload := false
	var saw_shot := false
	var start: Vector3 = enemy.global_position
	for frame in range(1800):
		await physics_frame
		if frame == 600:
			player.global_position = arena.to_global(Vector3(0, 0, -4))
		if frame == 1200:
			player.global_position = arena.to_global(Vector3(2, 0, 2.5))
		var before := Time.get_ticks_usec()
		ai._physics_process(1.0 / 60.0)
		samples.append(Time.get_ticks_usec() - before)
		actions[String(ai.utility_current.get("id", &""))] = true
		saw_reload = saw_reload or enemy.ammo.is_reloading
		saw_shot = saw_shot or enemy.ammo.magazine_rounds < 3
	samples.sort()
	check(saw_shot and saw_reload, "自主行动实际开火并完成空匣换弹调度")
	check(enemy.global_position.distance_to(start) > 0.2, "自主行动实际移动而非原地停摆")
	check(ai.action_selector.total_evaluated_count > 1000, "持续行动期间空间扫描保持推进")
	check(samples[1782] < 16000 and samples[-1] < 50000, "30秒完整AI循环P99低于16ms且没有50ms集中阻塞")
	print("RUNTIME actions=", actions.keys(), " P99=", samples[1782] / 1000.0, "ms max=", samples[-1] / 1000.0, "ms")
	# 已评分位置被准确执行，近战追踪持续更新。
	ai.reset_actions()
	ai.is_alerted = true
	ai.last_known_position = player.global_position
	var positions: Array = ai.tactics.get_engagement_candidate_points()
	var destination: Dictionary = {}
	for point: Vector3 in positions:
		destination = ai.tactics.assess_engagement_point(point, ai.last_known_position)
		if not destination.is_empty(): break
	check(not destination.is_empty(), "普通接敌可生成可达射击目的地")
	if not destination.is_empty():
		ai._start_utility_option({"id": &"engage", "destination": destination, "cost": 0.0}, true)
		ai.step_selected_action(1.0 / 60.0, true)
		check(ai.agent.target_position.is_equal_approx(destination.position), "普通接敌执行准确的评分目的地")
	ai.combat_type = ai.CombatType.MELEE
	ai._start_utility_option({"id": &"engage", "destination": {}, "cost": 0.0}, true)
	ai.last_known_position += Vector3.RIGHT
	ai.step_selected_action(1.0 / 60.0, true)
	check(ai.agent.target_position.is_equal_approx(ai.last_known_position), "近战追踪更新真实可见目标位置")
	print("UTILITY RUNTIME: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)
