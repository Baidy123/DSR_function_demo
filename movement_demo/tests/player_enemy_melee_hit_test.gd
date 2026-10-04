extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var combat = player.get_node("Combat")
	var slots = player.get_node("WeaponSlots")
	var enemy = scene.get_node("Arena/Enemy")
	enemy.get_node("AI").set_physics_process(false)
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	player.health.debug_invincible = false
	for door in scene.find_children("*", "AnimatableBody3D", true, false): door.collision_layer = 0
	for cover in get_nodes_in_group("cover_region"): cover.collision_layer = 0
	scene.get_node("CombatTest/CombatZone").global_position = Vector3.ZERO
	player.global_position = Vector3.ZERO
	await frames(3)
	var hp: float = player.health.health
	for mode in [combat.AimMode.PROBABILITY, combat.AimMode.SPREAD_CONE]:
		combat.aim_mode = mode
		combat.accuracy = 1.0
		player.receive_melee_hit(5.0, Vector3(0, 0, -1), 0.0, 0.2)
		check(combat.accuracy == 0.0, "近战清零当前准度模式" + str(mode))
		combat.end_frame(0.2, false)
		check(combat.accuracy == 0.0, "受击同帧不立刻恢复" + str(mode))
		slots.select_slot(1 - slots.active_slot)
		check(combat.accuracy == 0.0 and combat.accuracy_recovery_timer >= combat.weapon.get_aim_settings(combat.is_using_spread_cone()).delay, "切枪不能绕过准度清零" + str(mode))
	check(player.health.health == hp - 10.0, "近战伤害沿用玩家生命入口")
	var original_ticks := Engine.physics_ticks_per_second
	for ticks in [30, 60, 120]:
		Engine.physics_ticks_per_second = ticks
		player.global_position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		player.current_speed = 0.0
		await frames(3)
		player.receive_melee_hit(0.0, Vector3(0, 0, -1), 1.0, 0.2)
		player.set_physics_process(true)
		await frames(ceili(ticks * 0.3))
		player.set_physics_process(false)
		check(absf(player.global_position.z - 1.0) < 0.08, "玩家碰撞击退距离在物理帧率下稳定" + str(ticks))
	Engine.physics_ticks_per_second = original_ticks
	# 瞄准锁定分支同时横移，外力不能被下一帧主动移动覆盖或反复累加。
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	enemy.global_position = Vector3(0, 0, -3)
	await frames(3)
	Input.action_press("aim")
	Input.action_press("move_right")
	player.receive_melee_hit(0.0, Vector3(0, 0, -1), 1.0, 0.2)
	player.set_physics_process(true)
	await frames(ceili(original_ticks * 0.3))
	player.set_physics_process(false)
	Input.action_release("aim")
	Input.action_release("move_right")
	check(player.global_position.x > 0.05 and absf(player.global_position.z - 1.0) < 0.08, "锁定横移与击退合成且不重复积累外力")
	# 受击途中才按下瞄准，普通移动的外力也不能变成锁定分支的惯性。
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	await frames(3)
	player.receive_melee_hit(0.0, Vector3(0, 0, -1), 1.0, 0.2)
	player.set_physics_process(true)
	await frames(4)
	Input.action_press("aim")
	await frames(ceili(original_ticks * 0.3))
	player.set_physics_process(false)
	Input.action_release("aim")
	check(absf(player.global_position.z - 1.0) < 0.04, "击退途中切换瞄准不增加额外滑动")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(3, 2, 0.1)
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = Vector3(0, 1, 0.7)
	player.global_position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	await frames(3)
	player.receive_melee_hit(0.0, Vector3(0, 0, -1), 2.0, 0.2)
	player.set_physics_process(true)
	await frames(ceili(original_ticks * 0.3))
	player.set_physics_process(false)
	check(player.global_position.z < 0.7 and player.global_position.z > 0.05, "玩家击退受墙体碰撞阻挡")
	player.receive_melee_hit(0.0, Vector3(0, 0, -1), 1.0, 0.2)
	player.set_dialogue_active(true)
	check(player._melee_push_remaining == 0.0, "进入对话清理剩余击退")
	player.set_dialogue_active(false)
	player.receive_melee_hit(10000.0, Vector3(0, 0, -1), 1.0, 0.2)
	check(player.is_dead() and player._melee_push_remaining == 0.0, "致死攻击不留下击退")
	paused = false
	scene.queue_free()
	await process_frame
	await process_frame
	print("Player enemy melee hit: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
