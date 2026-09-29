extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	ai.cover_selection.debug_cover_selection = false
	player.get_node("Health").debug_invincible = true
	for body in get_nodes_in_group("cover_region"):
		body.collision_layer = 0
		body.remove_from_group("cover_region")
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(22.8, 0, -2)
	actor.face_direction(player.global_position - actor.global_position, 10.0)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	ai.context.sees_player = true
	for frame in range(60):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, true)
	check(actor.health == actor.max_health and ai.recent_damage_pressure == 0.0, "满血无受击情况下验证主动拉开")
	check(ai.context._reload_risk_aversion() > 0.0, "近身压力不再依赖受伤")
	var engage = ai.actions[&"engage"]
	var nearby: Dictionary = engage.assess_engagement_point(Vector3(24.5, 0, -2), ai.last_known_position)
	check(not nearby.is_empty(), "先退半步的候选无需一次达到4米距离带")
	var options: Array = ai.action_selector.assess_options(ai, true)
	var chosen: Dictionary = ai.action_selector.choose_option(options)
	check(chosen.get("id") == &"engage" and not chosen.destination.is_empty(), "Utility选择退让，不能被零代价原地射击压住")
	var start: Vector3 = actor.global_position
	var closest := INF
	for frame in range(360):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		closest = minf(closest, ai.context._horizontal_distance(player.global_position))
	var distance: float = ai.context._horizontal_distance(player.global_position)
	check(distance >= 3.4 and actor.global_position.distance_to(start) > 1.5, "真实移动将近身距离拉回交战距离附近")
	check(closest >= 1.1, "退路不会先冲向玩家")
	check(actor.shot_count > 0, "后退与稳定交火可以共同执行")
	var retreat_start: Vector3 = actor.global_position
	for frame in range(240):
		await physics_frame
		player.global_position = player.global_position.move_toward(actor.global_position, 0.7 / 60.0)
		ai._physics_process(1.0 / 60.0)
	check(actor.global_position.distance_to(retreat_start) > 0.5 and ai.context._horizontal_distance(player.global_position) > 2.0, "玩家持续逼近时会再次退让")
	var remembered: Vector3 = ai.last_known_position
	ai.context.sees_player = false
	var old_risk: float = ai.context._reload_risk_aversion()
	player.global_position += Vector3.RIGHT * 3.0
	check(is_equal_approx(old_risk, ai.context._reload_risk_aversion()) and ai.last_known_position == remembered, "失视时不读取真实玩家距离制造近身压力")
	print("CLOSE RANGE SPACING: %d/%d passed, distance=%.2f" % [checks - failures, checks, distance])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
