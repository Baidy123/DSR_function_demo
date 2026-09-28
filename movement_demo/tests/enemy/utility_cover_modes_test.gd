extends SceneTree

var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	ai.cover_selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	for frame in range(5): await physics_frame
	ai.is_alerted = true
	ai.last_known_position = player.global_position
	ai.was_seeing_player = true
	for frame in range(60):
		await physics_frame
		ai.action_selector.advance_evaluation(ai, true)
	var options: Array = ai.action_selector.assess_options(ai, true)
	var retreat: Dictionary = {}
	for option: Dictionary in options:
		if option.get("mode") == &"covering_retreat":
			retreat = option
			break
	check(not retreat.is_empty(), "掩护撤退作为共同评分候选")
	if retreat.is_empty():
		finish()
		return
	ai.cover.covering_retreat_chance = 0.0
	ai.cover.damage_force_sprint_chance = 1.0
	ai._start_utility_option(retreat, true)
	check(ai.cover.covering_retreat and ai.cover.utility_driven, "评分选定撤退不被旧概率覆盖")
	enemy.receive_hit(1.0, player.global_position)
	check(ai.cover.covering_retreat and ai.recent_damage_pressure > 0.0, "受击增加压力并等待统一重评，不用概率强切冲刺")
	ai.last_known_position = player.global_position
	enemy.global_position = retreat.destination.hide
	ai.cover.phase = ai.cover.Phase.HIDE
	ai.was_seeing_player = false
	ai.utility_unseen_seconds = 4.0
	for frame in range(3): await physics_frame
	options = ai.action_selector.assess_options(ai, false)
	var peek: Dictionary = {}
	for option: Dictionary in options:
		if option.get("mode") == &"peek":
			peek = option
			break
	check(not peek.is_empty(), "失视躲藏时可评估可达且有视线的探头点")
	if not peek.is_empty():
		check(not ai.action_selector.same_option(peek, retreat), "不同掩体动作模式有不同身份")
		ai._start_utility_option(peek, false)
		check(ai.cover.phase == ai.cover.Phase.PEEK_OUT and ai.cover.peek_position == peek.destination.position, "探头执行评分选中的位置")
		ai.step_selected_action(1.0 / 60.0, false)
		check(ai.agent.target_position.is_equal_approx(peek.destination.position), "探头导航不被躲藏目标覆盖")
		ai.resume_after_action(false, ai.last_known_position)
		check(ai.utility_rejected_attack_points.has(peek.destination.position), "无收获观察点记为已检查，避免无限重做")
	# 听声调查保持原路线，不能每次更新把目标重置到自己脚下。
	ai.reset_actions()
	ai.is_alerted = false
	ai.search.investigate_noise(player.global_position)
	var noise_target: Vector3 = ai.agent.target_position
	ai._start_utility_option({"id": &"search", "destination": {}, "cost": 0.0}, false)
	check(ai.agent.target_position == noise_target and ai._utility_current_valid(false), "听声调查保持路线且属于有效持续动作")
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("UTILITY COVER MODES: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)
