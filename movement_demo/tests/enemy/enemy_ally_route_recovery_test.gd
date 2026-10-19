extends "res://tests/enemy/enemy_ally_navigation_test.gd"

var reports := 0

func _run() -> void:
	await _setup()
	for actor in actors: actor.get_node("AI").set_physics_process(false)
	_make_corridor(false)
	await _reset(Vector3(-1.2, 0, 0), Vector3(0, 0, 0))
	var mover = actors[0]
	var blocker = actors[1]
	var context = mover.get_node("AI").context
	var selection = context.cover_selection
	var selector = mover.get_node("AI").action_selector
	mover.ally_path_blocked.connect(_record_report)
	# A real body capability restriction prevents the partner from yielding.
	# The tested mover still uses ordinary capsule movement and local avoidance.
	check(blocker.begin_melee(10.0), "真实友军进入不能移动的近战阶段，窄口无法临时让行")
	var preferred: Vector3 = arena.to_global(Vector3(3, 0, 0))
	var same_passage: Vector3 = arena.to_global(Vector3(3.5, 0, 0))
	var retreat: Vector3 = arena.to_global(Vector3(-3, 0, 0))
	var goals: Array[Vector3] = [preferred, same_passage, retreat]
	var before: Array = _options(context, goals)
	check(before.size() == 3 and selector.choose_option(before).destination.position == preferred, "实际阻塞前三个导航目的地仍参与原代价比较")
	for frame in 25: await _step_goal(preferred)
	check(reports == 0 and context._blocked_ally_paths.is_empty(), "短暂等待和局部回退不会立即封禁通道")
	for frame in 300:
		await _step_goal(preferred)
		if not context._blocked_ally_paths.is_empty(): break
	check(reports == 1 and context._blocked_ally_paths.size() == 1 and mover.global_position.x < blocker.global_position.x, "持续真实友军碰撞且没有身体进展后才登记有限堵路记忆")
	if context._blocked_ally_paths.is_empty():
		print("ALLY ROUTE RECOVERY: missing physical blockage report")
		quit(1)
		return
	var deadline: float = context._blocked_ally_paths[0].valid_until
	check(selection._path_to(mover.global_position, preferred).is_empty() and selection._path_to(mover.global_position, same_passage).is_empty(), "不同终点经过同一真实堵口都会暂时失效")
	check(not selection._path_to(mover.global_position, retreat).is_empty(), "同一动作向外脱离的合法路径继续可用")
	var chosen: Dictionary = selector.choose_option(_options(context, goals))
	check(chosen.get("id") == &"engage" and chosen.destination.position == retreat, "原Utility选择剩余代价最低目的地，不禁整个动作或指定固定次优")
	var repeated_rejected := true
	for frame in 45:
		await _step_goal(chosen.destination.position)
		repeated_rejected = repeated_rejected and selection._path_to(mover.global_position, preferred).is_empty() and selection._path_to(mover.global_position, same_passage).is_empty()
	check(repeated_rejected and context._blocked_ally_paths[0].valid_until == deadline and reports == 1, "转去其他位置后重复询问堵口仍被拒绝，查询和动作切换不续期记忆")
	var crossing := PackedVector3Array([blocker.global_position + Vector3.RIGHT * 0.72, blocker.global_position - Vector3.RIGHT * 2.0])
	var leaving := PackedVector3Array([blocker.global_position + Vector3.RIGHT * 0.72, blocker.global_position + Vector3.RIGHT * 2.0])
	check(context.is_ally_path_blocked(crossing[0], crossing) and not context.is_ally_path_blocked(leaving[0], leaving), "已经接触堵点时只允许向外退出，不能以终点更远为由穿过友军")
	# Keep the same frame's raw navigation cache; only the observed ally moves.
	selection._path_to(mover.global_position, preferred)
	blocker.cancel_melee()
	blocker.global_position = arena.to_global(Vector3(0, 0, 3))
	check(context.evidence_elapsed_seconds < deadline and not selection._path_to(mover.global_position, preferred).is_empty(), "友军移开后在截止时间前立即解除过滤，不等导航缓存或下一轮超时")
	context.update_evidence(STEP, false)
	check(context._blocked_ally_paths.is_empty() and selector.choose_option(_options(context, goals)).destination.position == preferred, "实际通路恢复后原最佳目的地重新参与普通Utility")
	for frame in 300:
		await _step_goal(preferred)
		if mover.global_position.distance_to(preferred) < 0.12: break
	check(mover.global_position.distance_to(preferred) < 0.12, "堵口解除后身体真实通过原通道到达目标")
	check(reports == 1, "无实际友军阻塞的后续行走不制造新堵路记录")

	# Lifecycle checks reuse a second real obstruction, never a synthetic memory.
	await _reset(Vector3(-1.2, 0, 0), Vector3(0, 0, 0))
	blocker.begin_melee(10.0)
	for frame in 300:
		await _step_goal(preferred)
		if not context._blocked_ally_paths.is_empty(): break
	check(not context._blocked_ally_paths.is_empty(), "生命周期对照再次取得真实堵路记录")
	context.reset_memory()
	check(context._blocked_ally_paths.is_empty(), "区域复位清除旧身体堵路证据")
	mover.clear_local_movement()
	for frame in 300:
		await _step_goal(preferred)
		if not context._blocked_ally_paths.is_empty(): break
	check(not context._blocked_ally_paths.is_empty(), "离场对照重新形成实际堵路")
	context.detach_environment()
	check(context._blocked_ally_paths.is_empty(), "离场立即清除旧区域堵路记忆")
	print("ALLY ROUTE RECOVERY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _record_report(_blocker: Node3D, _position: Vector3) -> void:
	reports += 1

func _step_goal(goal: Vector3) -> void:
	await physics_frame
	var actor = actors[0]
	actor.get_node("AI").context.update_evidence(STEP, false)
	var offset: Vector3 = goal - actor.global_position
	offset.y = 0.0
	actor.move_character(offset.normalized() * minf(1.0, offset.length() / maxf(0.001, actor.move_speed * STEP)), STEP)
	actors[1].move_character(Vector3.ZERO, STEP)

func _options(context, goals: Array[Vector3]) -> Array:
	var result: Array = []
	for index in goals.size():
		var path: PackedVector3Array = context.cover_selection._path_to(context.actor.global_position, goals[index])
		if not path.is_empty(): result.append({"id": &"engage", "destination": {"position": goals[index], "path": path}, "cost": float(index)})
	return result
