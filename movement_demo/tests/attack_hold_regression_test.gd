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
	# 本用例只隔离实际落脚点与旧目的地的中心射线差异；散布余量另有回归。
	enemy.weapon = enemy.weapon.duplicate()
	enemy.weapon.min_spread_angle_degrees = 0.0
	enemy.weapon.max_spread_angle_degrees = 0.0
	ai.cover_selection.debug_attack_points = false
	# 用户实机日志中已经到位的CoverA站姿及原采样目的地。
	enemy.global_position = Vector3(17.68982, 0, -1.900597)
	var destination := Vector3(17.63248, 0, -2.00449)
	var wall = scene.get_node("Arena/NavigationRegion3D/Environment/CoverA")
	# 固定复现时的碰撞几何；用户可继续在编辑器调整场景，测试不写回资源。
	var collision = wall.get_node("CollisionShape3D")
	collision.shape = collision.shape.duplicate()
	collision.shape.size = Vector3(1.2, 2.2, 6.890625)
	collision.position = Vector3(0, 0, 1.4453125)
	player.global_position = Vector3(20, 0, -3)
	for frame in range(60):
		await physics_frame
		if ai.is_arena_active() and not ai.cover_selection._path_to(enemy.global_position, enemy.global_position).is_empty():
			break
	# 固定复现：移动玩家后，两个相差约10厘米的位置有不同射界。
	var chosen := Vector3(16.8408, 0, 5.551192)
	var origin := chosen + Vector3.UP * 0.8
	var actual: Dictionary = ai.cover_selection.assess_attack_point(enemy.global_position, wall, origin, origin)
	var planned: Dictionary = ai.cover_selection.assess_attack_point(destination, wall, origin, origin)
	_check(actual.usable, "实际脚下仍能遮身并射击")
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
