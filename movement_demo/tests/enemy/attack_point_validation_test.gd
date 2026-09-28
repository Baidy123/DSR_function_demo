extends SceneTree

var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var selection = ai.cover_selection
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	enemy.shooting_enabled = false
	_check("提供攻击候选评估接口", selection.has_method("assess_attack_point"))
	if not checks.values().all(func(value): return value):
		scene.free()
		_finish()
		return
	selection.debug_attack_points = false
	# 等待实际导航同步，不依赖无窗口运行时若干帧恰好足够。
	for frame in range(60):
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(enemy.agent.get_navigation_map()) > 0 and not selection._path_to(enemy.global_position, enemy.global_position).is_empty():
			break
	await physics_frame
	_check("导航地图已同步且能生成路径", not selection._path_to(enemy.global_position, enemy.global_position).is_empty())
	var valid: Dictionary = {}
	var threat := Vector3.ZERO
	var wall: StaticBody3D
	var reasons := {}
	var available_points := 0
	var free_points := 0
	var reachable_points := 0
	# 用实际地图寻找一组满足几何条件的站位与已知目标，不绑定用户某个墙体的摆放坐标。
	for region in get_nodes_in_group("cover_region"):
		for point: Vector3 in region.get_attack_candidates():
			if not valid.is_empty():
				break
			var free: bool = ai.is_position_free(point)
			var reachable: bool = not selection._path_to(enemy.global_position, point).is_empty()
			free_points += int(free)
			reachable_points += int(reachable)
			if not free or not reachable:
				continue
			available_points += 1
			for angle in range(0, 360, 5):
				var direction := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle)))
				var target := point + direction * 5.0 + Vector3.UP * 0.8
				var result: Dictionary = selection.assess_attack_point(point, region, target, target)
				reasons[result.reason] = reasons.get(result.reason, 0) + 1
				if result.usable:
					valid = result
					threat = target
					wall = region
					break
	_check("真实地图存在可达且有散布射界的候选", not valid.is_empty())
	if valid.is_empty():
		print("可达且有空间的点=", available_points, "，空间=", free_points, "，可达=", reachable_points, "，方向评估=", reasons, "，起点=", enemy.global_position)
		print("导航最近点=", NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), enemy.global_position), "，区域迭代=", NavigationServer3D.region_get_iteration_id(ai.navigation_region.get_rid()))
		print("地图最近点=", NavigationServer3D.map_get_closest_point(enemy.agent.get_navigation_map(), enemy.global_position), "，自身路径=", selection._path_to(enemy.global_position, enemy.global_position))
		var example = get_nodes_in_group("cover_region")[0].get_attack_candidates()[0]
		print("示例=", example, "，投影=", NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), example), "，路径=", selection._path_to(enemy.global_position, example))
	if valid.is_empty():
		scene.free()
		_finish()
		return
	_check("遮身仅作信息保留，允许完全暴露", valid.protection >= 0.0 and valid.protection < 1.0)
	_check("合格点有路径与通畅射界", valid.reachable and valid.space_free and valid.clear_shot)
	var point: Vector3 = valid.position
	var other_side := point + Vector3.UP * 0.8 + (point + Vector3.UP * 0.8 - threat).normalized() * 5.0
	var arena = scene.get_node("Arena")
	var open_point: Vector3 = arena.to_global(Vector3(12, 0, 8))
	var open_target := open_point + Vector3.LEFT + Vector3.UP * 0.8
	var exposed: Dictionary = selection.assess_attack_point(open_point, wall, open_target, open_target)
	_check("其他条件通过时完全无遮身也允许架枪", exposed.reachable and exposed.space_free and exposed.clear_shot and exposed.in_range and exposed.usable and exposed.protection == 0.0)
	var outside: Dictionary = selection.assess_attack_point(arena.to_global(Vector3(13.2, 0, 8)), wall, threat, threat)
	_check("导航边界外淘汰", not outside.usable and not outside.reachable)
	var high: Dictionary = selection.assess_attack_point(point + Vector3.UP * 3, wall, threat, threat)
	_check("错误高度淘汰", not high.usable and not high.reachable)
	var collision = wall.get_node("CollisionShape3D")
	var inside: Vector3 = collision.global_position - Vector3.UP * collision.shape.size.y * 0.5
	var blocked: Dictionary = selection.assess_attack_point(inside, wall, threat, threat)
	_check("身体卡进掩体淘汰", not blocked.usable and not blocked.space_free)
	var behind: Vector3 = collision.global_position * 2 - (point + Vector3.UP * 0.8)
	var no_shot: Dictionary = selection.assess_attack_point(point, wall, behind, behind)
	_check("墙挡住枪口到目标的射线则淘汰", not no_shot.usable and not no_shot.clear_shot)
	var weapon = enemy.weapon
	enemy.weapon = weapon.duplicate()
	enemy.weapon.fire_range = 0.1
	var too_far: Dictionary = selection.assess_attack_point(point, wall, threat, threat)
	_check("超出当前武器射程淘汰", not too_far.usable and not too_far.in_range)
	enemy.weapon = null
	_check("无武器不产生合格攻击点", not selection.assess_attack_point(point, wall, threat, threat).usable)
	enemy.weapon = weapon
	var state_before = ai.state
	var destination_before: Vector3 = enemy.agent.target_position
	var shots_before: int = enemy.shot_count
	var before: Array = selection.get_attack_assessments(threat, threat)
	var expected_count := 0
	for region in get_nodes_in_group("cover_region"):
		expected_count += region.get_attack_candidates().size()
	player.global_position = point
	for frame in range(3):
		await physics_frame
	var after: Array = selection.get_attack_assessments(threat, threat)
	_check("隐藏玩家移动不影响固定已知位置评估", before == after)
	_check("评估不切换AI状态导航目标或开火", ai.state == state_before and enemy.agent.target_position == destination_before and enemy.shot_count == shots_before)
	_check("评估保留全部候选并给出原因", before.size() == expected_count and before.all(func(item): return not item.reason.is_empty()))
	# 用临时障碍验证空间查询，不改地图或导航资源。
	var obstacle := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	shape_node.shape = BoxShape3D.new()
	shape_node.shape.size = Vector3.ONE
	obstacle.add_child(shape_node)
	scene.add_child(obstacle)
	obstacle.global_position = point + Vector3.UP * 0.8
	for frame in range(3):
		await physics_frame
	_check("其他障碍占据身体空间时淘汰", not selection.assess_attack_point(point, wall, threat, threat).space_free)
	obstacle.free()
	player.global_position = open_point
	for frame in range(3):
		await physics_frame
	var preview = selection.get_node("AttackPreview")
	var debug_settings = root.get_node("DebugSettings")
	debug_settings.enabled = true
	selection.debug_attack_points = true
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = threat - Vector3.UP * 0.8
	preview.set_physics_process(false)
	preview.clear()
	preview._physics_process(1.0 / 60.0)
	_check("自动预览不会同帧检查整个区域", preview.assessments.is_empty())
	for frame in range(200):
		if preview.assessments.size() == expected_count:
			break
		preview._physics_process(1.0 / 60.0)
	_check("分帧检查完整结果与直接查询一致", preview.assessments == selection.get_attack_assessments(threat, threat))
	preview.clear()
	preview._physics_process(1.0 / 60.0)
	selection.debug_attack_points = false
	preview._physics_process(1.0 / 60.0)
	_check("关闭显示中止未完成批次", preview._pending.is_empty() and preview._results.is_empty() and preview.assessments.is_empty())
	selection.debug_attack_points = true
	preview.refresh()
	_check("运行显示为所有候选给出评估", preview.assessments.size() == expected_count)
	_check("大量样本共用网格且每个掩体只有一个标签", preview.get_children().size() == 7)
	debug_settings.enabled = false
	_check("总开关关闭立即清空攻击点并停止查询", not preview.is_physics_processing() and preview.assessments.is_empty() and preview.get_children().all(func(node): return not node.visible))
	preview.refresh()
	preview._physics_process(0.1)
	_check("手动刷新和细项开关不能绕过总开关", preview.assessments.is_empty() and preview._pending.is_empty())
	debug_settings.enabled = true
	preview.set_physics_process(false)
	preview.refresh()
	_check("重新开启总开关恢复攻击点评估", preview.assessments.size() == expected_count)
	var remembered: Array = preview.assessments.duplicate(true)
	ai.last_seen_position = other_side - Vector3.UP * 0.8
	preview.refresh()
	_check("更新玩家目击位置后重新评估点位", preview.assessments != remembered)
	ai.last_seen_position = threat - Vector3.UP * 0.8
	preview.refresh()
	player.global_position += Vector3.LEFT
	for frame in range(3):
		await physics_frame
	preview.refresh()
	_check("运行显示只使用最后目击位置", remembered == preview.assessments)
	selection.debug_attack_points = false
	preview.refresh()
	_check("关闭开关清空评估并隐藏标记", preview.assessments.is_empty() and preview.get_children().all(func(node): return not node.visible))
	selection.debug_attack_points = true
	ai.has_visual_memory = false
	preview.refresh()
	_check("没有目击记忆时不伪造评估", preview.assessments.is_empty())
	ai.has_visual_memory = true
	enemy.is_dead = true
	preview.refresh()
	_check("敌人死亡隐藏标记", preview.assessments.is_empty())
	enemy.is_dead = false
	ai.is_alerted = false
	preview.refresh()
	_check("结束警戒后隐藏标记", preview.assessments.is_empty())
	ai.is_alerted = true
	player.global_position = Vector3(-20, 0, 30)
	for frame in range(3):
		await physics_frame
	preview.refresh()
	_check("离场后清除标记", preview.assessments.is_empty())
	await _check_disconnected_path(scene, enemy, ai, selection, wall)
	scene.free()
	_finish()


func _check_disconnected_path(scene: Node, enemy: Node3D, ai: Node, selection: Node, wall: StaticBody3D) -> void:
	var original_region = ai.navigation_region
	var original_map: RID = enemy.agent.get_navigation_map()
	var original_position := enemy.global_position
	var fixture := NavigationRegion3D.new()
	var nav := NavigationMesh.new()
	nav.vertices = PackedVector3Array([
		Vector3(-2, 0.3, -2), Vector3(-2, 0.3, 2), Vector3(2, 0.3, 2), Vector3(2, 0.3, -2),
		Vector3(2.2, 0.3, -2), Vector3(2.2, 0.3, 2), Vector3(5, 0.3, 2), Vector3(5, 0.3, -2)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nav.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	fixture.navigation_mesh = nav
	fixture.position = Vector3(200, 0, 0)
	scene.add_child(fixture)
	var test_map := NavigationServer3D.map_create()
	# 0.2米间隙不能被默认较粗的顶点量化合并。
	NavigationServer3D.map_set_cell_size(test_map, 0.05)
	NavigationServer3D.map_set_active(test_map, true)
	NavigationServer3D.map_set_use_edge_connections(test_map, false)
	fixture.set_navigation_map(test_map)
	enemy.agent.set_navigation_map(test_map)
	ai.navigation_region = fixture
	enemy.global_position = Vector3(200, 0, 0)
	for frame in range(60):
		await physics_frame
		if not selection._path_to(enemy.global_position, enemy.global_position).is_empty():
			break
	var destination := Vector3(202.4, 0, 0)
	var projected := NavigationServer3D.region_get_closest_point(fixture.get_rid(), destination)
	var raw_path := NavigationServer3D.map_get_path(test_map, enemy.global_position, projected, true)
	_check("测试确实产生未到达终点的部分路径", not raw_path.is_empty() and raw_path[raw_path.size() - 1].distance_to(projected) > 0.1)
	var result: Dictionary = selection.assess_attack_point(destination, wall, Vector3(201, 0.8, 0), Vector3(201, 0.8, 0))
	_check("候选在另一导航孤岛也不能靠部分路径通过", not result.usable and not result.reachable)
	ai.navigation_region = original_region
	enemy.agent.set_navigation_map(original_map)
	enemy.global_position = original_position
	fixture.free()
	NavigationServer3D.free_rid(test_map)


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	print("攻击点评估：", checks.size(), " 项")
	quit(0 if checks.values().all(func(value): return value) else 1)
