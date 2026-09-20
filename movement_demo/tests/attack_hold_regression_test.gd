extends SceneTree

var failures: int = 0


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var action = ai.tactics.attack_position
	ai.set_physics_process(false)
	player.set_physics_process(false)
	enemy.shooting_enabled = false
	ai.cover_selection.debug_attack_points = false
	player.global_position = Vector3(20, 0, -3)
	for frame in range(60):
		await physics_frame
		if ai.is_arena_active() and not ai.cover_selection._path_to(enemy.global_position, enemy.global_position).is_empty():
			break
	# 在当前20度偏射边界下重建同类回归：实际脚下合格，旧目的地失效。
	var chosen := Vector3(19.92596, 0, -4.2821)
	var origin := chosen + Vector3.UP * 0.8
	var destination := Vector3.INF
	var wall: StaticBody3D
	for region in get_nodes_in_group("cover_region"):
		if destination.is_finite():
			break
		for point in region.get_attack_candidates():
			if point.distance_to(chosen) > 7.5 or not ai.cover_selection.assess_attack_point(point, region, origin, origin).usable:
				continue
			for offset in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				var old_point: Vector3 = point + offset * 0.1
				if not ai.cover_selection.assess_attack_point(old_point, region, origin, origin).usable:
					enemy.global_position = point
					destination = old_point
					wall = region
					break
			if destination.is_finite():
				break
	_check(destination.is_finite(), "找到实际站位与旧目的地有效性不同的复现")
	if not destination.is_finite():
		scene.free()
		quit(1)
		return
	var actual: Dictionary = ai.cover_selection.assess_attack_point(enemy.global_position, wall, origin, origin)
	var planned: Dictionary = ai.cover_selection.assess_attack_point(destination, wall, origin, origin)
	_check(actual.usable, "实际脚下仍能架枪射击")
	_check(not planned.usable, "原采样目的地已经失效")
	player.global_position = chosen
	enemy.look_at(chosen)
	for frame in range(3):
		await physics_frame
	ai.last_seen_position = chosen
	ai.has_visual_memory = true
	ai.is_alerted = true
	ai.state = ai.State.HOLD_POSITION
	action.phase = action.Phase.HOLD
	action.active_cover = wall
	action.destination = destination
	var sees: bool = ai.perception.can_see_player()
	action.step(0.3, sees)
	var retained: bool = action.phase == action.Phase.HOLD
	_check(sees, "实际视线仍然看见玩家")
	_check(retained, "脚下仍合格时保持墙角架枪")
	# 相同目的地在转移阶段仍须被拒绝，不能删掉途中复核。
	action.phase = action.Phase.MOVE
	action._recheck = 0.0
	action._remaining = 10.0
	action.step(0.3, sees)
	_check(not action.is_active(), "途中目的地失效仍退出转移")
	scene.free()
	quit(0 if failures == 0 else 1)
