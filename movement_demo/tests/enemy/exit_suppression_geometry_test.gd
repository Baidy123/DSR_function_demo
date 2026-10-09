extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var failures := 0
var checks := 0
var ai
var enemy
var player
var exits
var geometry: Dictionary = {}
var cover
var scene

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	enemy = scene.get_node("Arena/Enemy")
	ai = enemy.get_node("AI")
	player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	Fixture.configure_timing(enemy)
	Fixture.set_training_action(ai, &"suppression", true)
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	for body in ai.navigation_region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor": body.collision_layer = 0
	for old in get_nodes_in_group("cover_region"):
		old.collision_layer = 0
		old.remove_from_group("cover_region")
	cover = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = Vector3(22, 1.1, -2)
	cover.get_node("CollisionShape3D").shape = BoxShape3D.new()
	cover.get_node("CollisionShape3D").shape.size = Vector3(0.8, 2.2, 6)
	enemy.global_position = Vector3(24.5, 0, -2)
	player.global_position = Vector3(20.8, 0, -2)
	ai.is_alerted = true
	ai.has_visual_memory = true
	# 新归属规则要求冻结线索确实在墙后，不能仅靠近端部。
	ai.last_seen_position = Vector3(20.8, 0, -2)
	ai.last_known_position = ai.last_seen_position
	ai.utility_unseen_seconds = 0.0
	exits = ai.actions[&"suppression"]
	await _sync()
	check(exits.preview_candidate(&"exit_sweep").is_empty() and not exits.begin({"plan": &"exit_sweep"}, false), "开放出口也不产生或执行已移除的压制方案")
	_refresh_geometry()
	check(not geometry.first.is_empty() and not geometry.second.is_empty(), "搜索共享几何仍保留两个可通行出口")
	var all_at_exits := true
	for point: Vector3 in geometry.first + geometry.second:
		all_at_exits = all_at_exits and absf(point.x - 22.85) < 0.01 and absf(point.z + 2.0) >= 3.4 and absf(point.z + 2.0) <= 3.8
	check(all_at_exits, "所有目标都在身体绕出墙后的端部入口，不再使用宽扇环")
	var original_aim: Vector3 = exits.aim_point
	var original_shots: int = exits._shots_remaining
	_refresh_geometry()
	check(exits.aim_point == original_aim and exits._shots_remaining == original_shots and not exits.active, "共享几何预览不改写执行瞄准点或连射状态")
	enemy.global_position = Vector3(23.2, 0, -4.7)
	await _sync()
	_refresh_geometry()
	var asymmetric: Dictionary = geometry.duplicate(true)
	check(not asymmetric.is_empty() and exits.preview_candidate(&"point").is_empty(), "几何可辨识不代表能向墙后记忆点开火")
	player.global_position = Vector3(22, 0, 1.45)
	await _sync()
	_refresh_geometry()
	check(geometry == asymmetric, "移动隐藏玩家不改变冻结几何查询")
	enemy.global_position = Vector3(24.5, 0, -2)
	await _sync()
	# 墙与掩体之间仅0.55米；射线能穿过，0.7米直径身体不能通过。
	var wall = _wall(Vector3(22, 1.1, -5.65), Vector3(4, 2.2, 0.2))
	await _sync()
	check(ai.cover_selection.has_clear_line(enemy.get_shot_origin(), Vector3(22.85, 0.8, -5.45)), "窄缝中心射线仍畅通，不能仅靠射线排除")
	_refresh_geometry()
	check(geometry.first.is_empty() and not geometry.second.is_empty(), "身体不能通过的窄缝从共享几何中剔除")
	check(exits.collect_candidates(false).is_empty(), "几何只有单端也不会给盲射或出口方案虚假收益")
	wall.global_position.z = -6.05
	await _sync()
	_refresh_geometry()
	check(not geometry.first.is_empty() and not geometry.second.is_empty(), "墙间隙扩大到能容纳身体和余量后恢复共享通行几何")
	wall.global_position.z = -5.1
	await _sync()
	_refresh_geometry()
	check(geometry.first.is_empty() and not geometry.second.is_empty(), "一端贴墙仍保留另一端通行几何")
	var other_wall = _wall(Vector3(22, 1.1, 1.1), Vector3(4, 2.2, 0.2))
	await _sync()
	_refresh_geometry()
	check(geometry.first.is_empty() and geometry.second.is_empty(), "两端贴墙后共享几何报告无通路")
	wall.collision_layer = 0
	other_wall.collision_layer = 0
	await _sync()
	# 出口落脚点空闲，但隐藏侧入口被障碍封住；完整身体扫掠仍必须失败。
	wall.global_position = Vector3(21.25, 1.1, -5.6)
	wall.get_node("CollisionShape3D").shape.size = Vector3(0.2, 2.2, 1.2)
	wall.collision_layer = 1
	await _sync()
	check(ai.context.is_position_free(Vector3(22, 0, -5.45)), "通道中点能站人")
	_refresh_geometry()
	check(geometry.first.is_empty(), "隐藏侧入口受阻时不能把孤立落脚点当出口")
	wall.collision_layer = 0
	ai.last_seen_position = Vector3(22.8, 0, -2)
	await _sync()
	_refresh_geometry()
	check(geometry.is_empty(), "记忆位于墙正面中部时不推断为墙后玩家出口")
	ai.last_seen_position = Vector3(20.8, 0, -2)
	# 无关掩体虽靠近记忆，但被其他实体遮住，不能取代可信目标掩体。
	var irrelevant = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(irrelevant)
	irrelevant.global_position = Vector3(22.8, 1.1, -5.8)
	irrelevant.get_node("CollisionShape3D").shape = BoxShape3D.new()
	irrelevant.get_node("CollisionShape3D").shape.size = Vector3(0.2, 2.2, 0.2)
	wall.global_position = Vector3(23.6, 1.1, -3.9)
	wall.get_node("CollisionShape3D").shape.size = Vector3(0.7, 2.2, 0.7)
	wall.collision_layer = 1
	await _sync()
	_refresh_geometry()
	check(geometry.get("body") == cover, "无关近墙不遮挡冻结线索时只保留实际遮挡掩体")
	irrelevant.collision_layer = 0
	irrelevant.remove_from_group("cover_region")
	wall.collision_layer = 0
	# 同时变换观察者和记忆，验证局部出口语义及世界身体尺寸。
	cover.rotation.y = 0.6
	cover.scale = Vector3(1.3, 1, 0.8)
	var box = cover.get_node("CollisionShape3D")
	enemy.global_position = box.to_global(Vector3(2.5, -1.1, 0))
	ai.last_seen_position = box.to_global(Vector3(-1.2, -1.1, 0))
	await _sync()
	_refresh_geometry()
	check(not geometry.is_empty() and not geometry.first.is_empty() and not geometry.second.is_empty(), "旋转和非均匀缩放后两端通道仍可用")
	all_at_exits = true
	for target: Vector3 in geometry.first + geometry.second:
		var local: Vector3 = box.to_local(target - Vector3.UP * 0.8)
		all_at_exits = all_at_exits and absf(local.x - (0.4 + 0.45 / 1.3)) < 0.01 and absf(local.z) > 3.0
	check(all_at_exits, "旋转缩放后目标仍在所属出口")
	cover.rotation = Vector3.ZERO
	cover.scale = Vector3.ONE
	enemy.global_position = Vector3(22, 0, -7)
	ai.last_seen_position = Vector3(22, 0, 1.8)
	await _sync()
	_refresh_geometry()
	check(not geometry.is_empty(), "从短边观察时也能推断通行几何")
	all_at_exits = true
	for target: Vector3 in geometry.first + geometry.second:
		all_at_exits = all_at_exits and absf(target.z + 5.45) < 0.01 and absf(target.x - 22.0) > 0.8
	check(all_at_exits, "短边出口沿对应墙面两端生成，不固定使用长轴")
	cover.get_node("CollisionShape3D").disabled = true
	await _sync()
	_refresh_geometry()
	check(geometry.is_empty(), "停用碰撞的掩体不能继续生成通行几何")
	cover.get_node("CollisionShape3D").disabled = false
	await _check_turning()
	print("EXIT SUPPRESSION GEOMETRY: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _check_turning() -> void:
	enemy.global_position = Vector3(24.5, 0, -2)
	ai.last_seen_position = Vector3(20.8, 0, -2)
	player.global_position = Vector3(20.8, 0, -2)
	await _sync()
	_refresh_geometry()
	var target: Vector3 = geometry.second[0]
	enemy.look_at(target)
	enemy.has_aim = true
	enemy.aim_acquired = true
	enemy.aim_direction = (geometry.first[0] - enemy.get_shot_origin()).normalized()
	enemy.shot_cooldown = 0.0
	ai.context.fire.fire_pause_remaining = 0.0
	var shots: int = enemy.shot_count
	var remaining: int = exits._shots_remaining
	ai.context.fire.update(1.0 / 60.0, false, false, {"owner": &"suppression", "mode": &"memory", "point": target})
	check(enemy.shot_count == shots and exits._shots_remaining == remaining, "直接火控诊断：已有锁定也不能在转枪途中开火或消耗波次")
	for frame in 120:
		await physics_frame
		enemy.face_direction(target - enemy.global_position, 1.0 / 60.0)
		ai.context.fire.update(1.0 / 60.0, false, false, {"owner": &"suppression", "mode": &"memory", "point": target})
		if enemy.shot_count > shots: break
	check(enemy.shot_count > shots, "直接火控诊断：枪口跟上合法空区域后真实开火")
	check(enemy.last_shot_direction.angle_to(target - enemy.get_shot_origin()) <= enemy.AIM_ACQUIRE_ANGLE + 0.001, "满准度真实子弹朝向请求区域而非转枪途中")
	var maximum_us := 0
	for frame in 60:
		await physics_frame
		var started := Time.get_ticks_usec()
		_refresh_geometry()
		exits.preview_candidate(&"exit_sweep")
		maximum_us = maxi(maximum_us, Time.get_ticks_usec() - started)
	check(maximum_us < 20000, "共享通行几何与已移除方案拒绝合计小于20毫秒")
	print("EXIT GEOMETRY BUDGET: max %.3f ms" % (maximum_us / 1000.0))

func _refresh_geometry() -> void:
	geometry = ai.cover_selection.suppression_geometry(ai.last_seen_position)

func _wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	collision.shape.size = size
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = position
	return wall

func _sync() -> void:
	for frame in 3: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
