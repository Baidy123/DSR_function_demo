extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var arena = scene.get_node("Arena")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	var attack_resource = load("res://resources/enemy/actions/attack_position.tres")
	ai.unit_type.available_actions.append(attack_resource)
	ai.training.allowed_actions.append(attack_resource)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"attack_position", true)
	ai.cover_selection.debug_cover_selection = false
	player.get_node("Health").debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	for frame in range(5): await physics_frame
	var target: Vector3 = player.global_position + Vector3.UP * 0.8
	var blocked := Vector3.INF
	for body in get_nodes_in_group("cover_region"):
		if not ai.navigation_region.is_ancestor_of(body): continue
		for point: Vector3 in body.get_attack_candidates():
			var origin := point + Vector3.UP * 0.8
			if point.distance_to(player.global_position) > 9.0 or not ai.is_position_free(point): continue
			if ai.cover_selection.has_clear_line(origin, target) and not ai.cover_selection.has_clear_shot_cone(origin, target - origin, enemy.get_max_shot_deviation_degrees(), origin.distance_to(target), body):
				blocked = point
				break
		if blocked.is_finite(): break
	check(blocked.is_finite(), "真实地图找到中心视线通畅但散布撞掩体的位置")
	if not blocked.is_finite():
		finish()
		return
	enemy.global_position = blocked
	enemy.look_at(player.global_position)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	ai.state = ai.State.HOLD_POSITION
	for frame in range(3): await physics_frame
	check(ai.perception.can_see_player(), "问题位置确实能看见玩家")
	var shots: int = enemy.shot_count
	for frame in range(180):
		enemy.face_direction(player.global_position - enemy.global_position, 1.0 / 60.0)
		ai.tactics.update_shooting(1.0 / 60.0, true, false)
	check(enemy.shot_count == shots, "普通交战不能在射界被自身掩体遮挡时开火")
	var options: Array = ai.action_selector.assess_options(ai, true)
	var nearby_clear := false
	for point: Vector3 in ai.tactics.get_engagement_candidate_points():
		if point.distance_to(blocked) <= 1.01 and not ai.tactics.assess_engagement_point(point, ai.last_known_position).is_empty():
			nearby_clear = true
	check(nearby_clear, "半米侧移已有射界时，普通交战候选不能漏掉附近位置")
	var standing: Array = options.filter(func(o): return o.id == &"engage" and o.destination.is_empty())
	check(standing.size() == 1 and standing[0].breakdown.unavailable_seconds == ai.utility_horizon_seconds, "被遮挡站位不被评为可持续开火")
	# 同一规则覆盖枪口尚未跟到真实目标、仍朝墙的情况。
	if ai.tactics.has_method("has_clear_firing_lane"):
		check(not ai.tactics.has_clear_firing_lane(enemy.get_shot_origin(), Vector3.ZERO, 5.0), "无效瞄准方向拒绝开火")
	var cover_hits := 0
	for frame in range(600):
		await physics_frame
		var before: int = enemy.shot_count
		ai._physics_process(1.0 / 60.0)
		# 带画面复现时保存关键帧；默认自动回归不读写截图。
		if "--capture" in OS.get_cmdline_user_args() and frame in [0, 180, 360, 599]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://logs/recovery-visual-%d.png" % frame)
			print("VISUAL frame=", frame, " position=", enemy.global_position, " action=", ai.utility_current.get("id"), " shots=", enemy.shot_count)
		if enemy.shot_count > before and is_instance_valid(enemy.last_shot_collider) and enemy.last_shot_collider.is_in_group("cover_region"):
			cover_hits += 1
	check(enemy.global_position.distance_to(blocked) > 0.3, "统一决策会离开错误射击位，不仅原地禁射")
	check(cover_hits == 0, "真实移动交战过程不向掩体开火")
	check(enemy.shot_count > shots, "启用攻击占位后能换到可射位置并恢复开火")
	print("BLOCKED POSITION ", blocked)
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("UTILITY FIRING LANE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
