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
	player.health.debug_invincible = true
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_cover"])
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	enemy.global_position = Vector3(22, 0, 4)
	player.global_position = Vector3(24, 0, -4.5)
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	check(ai.perception.can_see_player(), "掩体推进起点真实目击玩家")
	# 用真实受击建立避险需求；不指定赢家、不篡改统一权重或掩体几何。
	enemy.receive_hit(65.0, player.global_position)
	var initial_distance: float = enemy.global_position.distance_to(player.global_position)
	var saw_cover := false
	var reached_shelter := false
	var completed := false
	var selected_point := Vector3.INF
	var selected_origin := Vector3.ZERO
	var budget_ok := true
	var peak_query_usec := 0
	for frame in 300:
		await physics_frame
		var previous_id: StringName = ai.utility_current.get("id", &"")
		ai._physics_process(1.0 / 60.0)
		budget_ok = budget_ok and ai.context.spatial.last_evaluated_count <= ai.context.spatial.EVALUATION_POINTS_PER_FRAME
		peak_query_usec = maxi(peak_query_usec, ai.context.spatial.last_evaluation_usec)
		if ai.utility_current.get("id") == &"melee_cover":
			if not saw_cover:
				selected_point = ai.utility_current.destination.hide
				selected_origin = enemy.global_position
			saw_cover = true
		if saw_cover and ai.context.cover_selection.is_hidden_at(enemy.global_position, player.global_position + Vector3.UP * 0.8):
			reached_shelter = reached_shelter or enemy.global_position.distance_to(player.global_position) < initial_distance - 0.5
		if previous_id == &"melee_cover" and ai.utility_current.get("id") != &"melee_cover":
			completed = true
			if reached_shelter: break
	check(saw_cover, "真实受击后原Utility自主选中掩体接近")
	check(selected_point.is_finite() and selected_point.distance_to(player.global_position) < selected_origin.distance_to(player.global_position), "选中掩体落点确实缩短接敌距离")
	check(reached_shelter, "实际走到遮挡后方并拉近与玩家的距离")
	check(completed, "到达掩体后释放本段推进，不永久原地躲藏")
	check(budget_ok, "近战掩体几何仍通过共享分帧点数预算")
	check(peak_query_usec < 20000, "近战掩体空间评估保留20毫秒验收门槛")
	var action = ai.actions[&"melee_cover"]
	ai.context.utility_unseen_seconds = 6.0
	check(action.collect_candidates(false).is_empty(), "旧目击超时后掩体推进退出并交回搜索")
	# 动态堵住已选落点：导航仍是原地图，执行前的真实身体检查必须拒绝旧点。
	player.combat.cancel_reload()
	player.global_position = Vector3(24, 0, -4.5)
	enemy.reset_target()
	enemy.global_position = Vector3(22, 0, 4)
	enemy.look_at(player.global_position)
	for frame in 4: await physics_frame
	enemy.receive_hit(65.0, player.global_position)
	var blocked_plan: Dictionary = {}
	for frame in 60:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if ai.utility_current.get("id") == &"melee_cover":
			blocked_plan = ai.utility_current.duplicate(true)
			break
	check(not blocked_plan.is_empty(), "受阻检查由Utility实际选出推进落点")
	if not blocked_plan.is_empty():
		var remembered: Vector3 = ai.context.last_known_position
		player.global_position = Vector3(12, 0, 8)
		await physics_frame
		check(not ai.perception.can_see_player(), "信息隔离用例中的玩家确实不可见")
		ai.context.update_evidence(0.0, false)
		var before: Array = action.collect_candidates(false)
		check(not before.is_empty(), "信息隔离对比包含真实有效的掩体候选")
		player.global_position = Vector3(12, 0, 9)
		player.combat.ammo.infinite_reserve = true
		player.combat.ammo.magazine_rounds = 0
		player.combat.request_reload()
		await physics_frame
		ai.context.update_evidence(0.0, false)
		var after: Array = action.collect_candidates(false)
		check(before == after and ai.context.last_known_position == remembered, "移动隐藏玩家并换弹不改变有效掩体候选")
		player.combat.cancel_reload()
		player.global_position = Vector3(24, 0, -4.5)
		await physics_frame
		ai.context.update_evidence(0.0, ai.perception.can_see_player())
		var blocker := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 2.0, 1.2)
		collision.shape = box
		blocker.add_child(collision)
		root.add_child(blocker)
		blocker.global_position = blocked_plan.destination.hide + Vector3.UP
		await physics_frame
		check(not action.validate(blocked_plan, ai.perception.can_see_player()), "动态封堵后旧掩体落点无法通过执行复核")
		for frame in 36:
			await physics_frame
			ai._physics_process(1.0 / 60.0)
		check(ai.utility_current.get("id") != &"melee_cover" or ai.utility_current.destination.hide.distance_to(blocked_plan.destination.hide) > 0.5, "受阻后实际取消旧路线并重新决策")
		blocker.queue_free()
		await physics_frame
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	check(not ai.actions.has(&"melee_cover") and not action.is_enabled(), "撤销训练后不再装配或运行掩体接近")
	var preset = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	preset.set_setting(&"melee_tactics", &"rush_seconds", 0.7)
	preset.set_setting(&"melee_tactics", &"cover_minimum_progress", 0.9)
	DirAccess.make_dir_recursive_absolute("res://logs")
	check(ResourceSaver.save(preset, "res://logs/melee_tactics_training.tres") == OK, "近战训练参数可保存")
	var restored = load("res://logs/melee_tactics_training.tres")
	check(is_equal_approx(restored.setting(&"melee_tactics", &"rush_seconds"), 0.7) and is_equal_approx(restored.setting(&"melee_tactics", &"cover_minimum_progress"), 0.9), "近战参数重载保留训练显式覆盖")
	print("Melee cover: %d/%d passed; peak query %d us" % [checks - failures, checks, peak_query_usec])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
