extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var selector = load("res://scripts/enemy/services/enemy_spatial_evaluator.gd").new()
	check(selector.has_method("advance_evaluation"), "空间评估具有逐帧预算入口")
	if failures:
		quit(1)
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var ai = scene.get_node("Arena/Enemy/AI")
	# 明确本测试所需动作；用户可在保存的训练中关闭攻击占位。
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"attack_position", true)
	selector = ai.context.spatial
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	ai.cover_selection.debug_attack_points = false
	player.global_position = scene.get_node("Arena").to_global(Vector3(0, 0, 2.5))
	await physics_frame
	await physics_frame
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	var attack_job: Dictionary = selector.jobs.filter(func(job): return job.channel == &"attack_position")[0]
	var maximum_us := 0
	var assessed_us := 0
	var total := 0
	for frame in range(180):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, true)
		maximum_us = maxi(maximum_us, selector.last_evaluation_usec)
		check(selector.last_evaluated_count <= selector.EVALUATION_POINTS_PER_FRAME, "单帧空间查询数量受限")
		total += selector.last_evaluated_count
		var before: int = selector.total_evaluated_count
		var started := Time.get_ticks_usec()
		ai.action_selector.assess_options(ai, true)
		assessed_us = maxi(assessed_us, Time.get_ticks_usec() - started)
		check(selector.total_evaluated_count == before, "同帧多次请求不重复扫描")
	check(attack_job.completed_passes >= 1, "预算扫描最终覆盖全部攻击采样点")
	check(maximum_us < 20000 and assessed_us < 20000, "真实场景单次评估不再超过20毫秒")
	var completed_before: int = attack_job.completed_passes
	for frame in range(180):
		await physics_frame
		ai.last_seen_position.x += 0.03
		ai.last_known_position = ai.last_seen_position
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, true)
	check(attack_job.completed_passes > completed_before, "持续移动的已知目标不会令后段候选永远得不到检查")
	selector.reset_evaluation()
	check(selector.total_evaluated_count == 0 and selector.cached_candidate_count() == 0, "刷新清理上一轮评估缓存")
	print("Utility budget: %d checks, %d failures; max advance %.3f ms, assess %.3f ms, evaluated %d" % [checks, failures, maximum_us / 1000.0, assessed_us / 1000.0, total])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
