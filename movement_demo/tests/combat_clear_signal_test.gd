extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const EnemyFixture := preload("res://tests/enemy/enemy_fire_fixture.gd")
const WATCHDOG_SECONDS := 15.0
const MAX_SETTLE_FRAMES := 8
const MAX_LIFECYCLE_FRAMES := 120

var _failures := 0
var _cleared_count := 0
var _cleared_region: Node
var _finished := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)

	var scene = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene

	var tree := scene.get_tree()
	var arena = scene.get_node("Arena")
	var player: Node3D = scene.get_node("Player")
	var enemies: Array[Node] = EnemyFixture.members(arena)
	player.set_physics_process(false)
	for enemy in enemies:
		enemy.set_physics_process(false)

	_check(await _wait_for_registration(tree, arena, enemies), "敌人完成场景生命周期登记")
	_check(arena.has_signal("combat_cleared"), "竞技场暴露 combat_cleared 信号")
	if not arena.has_signal("combat_cleared"):
		_finish(scene)
		return
	arena.connect(&"combat_cleared", _on_combat_cleared)

	player.global_position = arena.to_global(Vector3(-4, 0, 0))
	await _wait_physics_frames(tree, MAX_SETTLE_FRAMES)
	_kill_enemies(enemies)
	await _wait_physics_frames(tree, MAX_SETTLE_FRAMES)
	_check(_cleared_count == 1, "全部登记敌人死亡时发出一次清场信号")
	_check(_cleared_region == arena, "清场信号携带发出信号的竞技场")

	_kill_enemies(enemies)
	await _wait_physics_frames(tree, MAX_SETTLE_FRAMES)
	_check(_cleared_count == 1, "同一进场周期不重复清场")

	player.global_position = arena.to_global(Vector3(-15, 0, 0))
	_check(await _wait_for_exit_reset(tree, arena, player, enemies), "最后一名玩家离场后复位目标并解除清场状态")

	player.global_position = arena.to_global(Vector3(-4, 0, 0))
	_check(await _wait_for_reentry(tree, arena, player, enemies), "重新进场后玩家与登记敌人恢复活动")
	_kill_enemies(enemies)
	_check(await _wait_for_cleared_count(tree, 2), "重新进场并清场后再次发出信号")
	_check(_cleared_count == 2, "第二个进场周期只发出一次清场信号")

	_finish(scene)


func _on_combat_cleared(region: Node) -> void:
	_cleared_count += 1
	_cleared_region = region


func _wait_for_registration(tree: SceneTree, arena: Node, enemies: Array) -> bool:
	for _frame in range(MAX_LIFECYCLE_FRAMES):
		if enemies.all(func(enemy): return arena.enemies.has(enemy)):
			return true
		await tree.physics_frame
	return false


func _wait_for_exit_reset(tree: SceneTree, arena: Node, player: Node, enemies: Array) -> bool:
	for _frame in range(MAX_LIFECYCLE_FRAMES):
		if not arena.players_inside.has(player) and enemies.all(func(enemy): return not enemy.is_dead):
			return true
		await tree.physics_frame
	return false


func _wait_for_reentry(tree: SceneTree, arena: Node, player: Node, enemies: Array) -> bool:
	for _frame in range(MAX_LIFECYCLE_FRAMES):
		if arena.players_inside.has(player) and enemies.all(func(enemy): return arena.enemies.has(enemy) and not enemy.is_dead):
			for _settle in range(MAX_SETTLE_FRAMES):
				await tree.physics_frame
			return true
		await tree.physics_frame
	return false


func _kill_enemies(enemies: Array) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead:
			enemy.receive_hit(10000.0)


func _wait_for_cleared_count(tree: SceneTree, expected: int) -> bool:
	for _frame in range(MAX_SETTLE_FRAMES):
		if _cleared_count >= expected:
			return true
		await tree.physics_frame
	return false


func _wait_physics_frames(tree: SceneTree, frame_count: int) -> void:
	for _frame in range(frame_count):
		await tree.physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error(label)


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	push_error("combat clear signal test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	scene.queue_free()
	print("combat clear signal checks: %s" % ("all passed" if _failures == 0 else "%d failed" % _failures))
	quit(1 if _failures > 0 else 0)
