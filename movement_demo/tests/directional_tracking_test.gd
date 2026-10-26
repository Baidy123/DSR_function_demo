extends SceneTree

var checks := 0
var failed := 0
var world: Node3D
var player
var combat
var target: StaticBody3D


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)


func _run() -> void:
	# 真实玩家、物理目标和战斗区；手动推进原玩家帧流程，不依赖用户保存的地图／枪械调参。
	Engine.physics_ticks_per_second = 240
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.collision_mask = 1
	zone.add_to_group("combat_zone")
	_add_box(zone, Vector3(100, 10, 100), Vector3.ZERO)
	world.add_child(zone)
	player = load("res://scenes/player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	combat = player.get_node("Combat")
	target = StaticBody3D.new()
	target.add_to_group("combat_target")
	_add_box(target, Vector3(0.6, 1.8, 0.6), Vector3(0, 0.9, 0))
	world.add_child(target)
	for frame in 4: await physics_frame
	for mode in 3:
		await _prepare(mode)
		check(combat.locked_target == target and combat.can_combat(), "Mode %d: actual physics visibility acquires the target" % mode)
		for direction in [Vector3.FORWARD, Vector3.BACK]:
			await _prepare(mode)
			combat.accuracy_recovery_timer = 0.2
			for frame in 20: await _tick(0.05, direction * 0.1)
			check(is_equal_approx(combat.accuracy, 1.0), "Mode %d: sustained approach/retreat allows full recovery (%s)" % [mode, direction])
		var left: float = await _loss(mode, Vector3.LEFT * 0.6, 0.2)
		var right: float = await _loss(mode, Vector3.RIGHT * 0.6, 0.2)
		check(left > 0 and is_equal_approx(left, right), "Mode %d: lateral movement retains symmetric penalties" % mode)
		var diagonal: float = await _loss(mode, Vector3(1, 0, -1).normalized() * 0.6, 0.2)
		check(diagonal > 0 and diagonal < right, "Mode %d: diagonal movement costs less than equal-speed lateral movement" % mode)
		var near_parallel: float = await _loss(mode, Vector3(sin(deg_to_rad(3)), 0, -cos(deg_to_rad(3))) * 0.6, 0.2)
		check(is_zero_approx(near_parallel), "Mode %d: small navigation deviations are inside the parallel tolerance" % mode)
		await _prepare(mode)
		combat.accuracy = 0.4
		await _tick(0.1, Vector3.RIGHT * 0.4)
		var before: float = combat.accuracy
		await _tick(0.1, target.position.normalized() * 0.2)
		check(combat.accuracy > before and combat.accuracy < 1, "Mode %d: turning radial releases the recovery restriction gradually" % mode)
		await _prepare(mode)
		combat.accuracy = 0.1
		await _tick(0.1, Vector3.RIGHT * 0.4)
		check(is_equal_approx(combat.accuracy, 0.15), "Mode %d: lateral motion neither raises nor further lowers damage below the tracking floor" % mode)
	await _boundaries()
	await _lifecycle()
	world.queue_free()
	await process_frame
	print("DIRECTIONAL TRACKING: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)


func _add_box(body: CollisionObject3D, size: Vector3, offset: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = offset
	body.add_child(collision)


func _prepare(mode: int = 0, point: Vector3 = Vector3(0, 0, -10)) -> void:
	var gun := WeaponData.new()
	gun.aim_range = 50
	gun.cone_angle_degrees = 180
	gun.shot_noise = null
	gun.initial_accuracy = 0.5
	gun.convergence_seconds = 2
	gun.target_move_accuracy_loss_per_meter_slow = 0.1
	gun.target_move_accuracy_loss_per_meter_fast = 0.2
	gun.target_move_minimum_accuracy = 0.3
	gun.player_move_accuracy_loss_per_meter = 0.1
	gun.moving_accuracy_cap = 0.5
	gun.min_spread_angle_degrees = 0
	gun.max_spread_angle_degrees = 20
	gun.initial_spread_angle_degrees = 10
	gun.target_move_spread_degrees_per_meter_slow = 2
	gun.target_move_spread_degrees_per_meter_fast = 4
	gun.target_move_max_spread_angle_degrees = 14
	gun.shot_max_spread_angle_degrees = 18
	if mode == 2:
		gun.fire_mode = WeaponData.FireMode.SHOTGUN
		gun.shotgun.starting_stability = 0.5
		gun.shotgun.tracking_loss_per_meter = Vector2(0.1, 0.2)
		gun.shotgun.tracking_stability_floor = 0.3
	combat.aim_mode = combat.AimMode.PROBABILITY if mode == 0 else combat.AimMode.SPREAD_CONE
	combat.equip_weapon(gun)
	if combat.get("tracking_parallel_tolerance_degrees") != null: combat.tracking_parallel_tolerance_degrees = 5
	player.position = Vector3.ZERO
	player.visual.rotation = Vector3.ZERO
	target.position = point
	combat.accuracy = 0.8
	combat.accuracy_recovery_timer = 0
	await physics_frame
	combat.begin_frame(0, true)


func _tick(delta: float, offset: Vector3, player_offset: Vector3 = Vector3.ZERO) -> void:
	combat.begin_frame(delta, true)
	target.position += offset
	player.position += player_offset
	await physics_frame
	combat.end_frame(delta, not player_offset.is_zero_approx())


func _loss(mode: int, displacement: Vector3, delta: float) -> float:
	# 前后位置关于连线对称，避免把采样方向差异误认为惩罚左右不对称。
	await _prepare(mode, Vector3(0, 0, -10) - displacement * 0.5)
	combat.accuracy = 1
	combat.accuracy_recovery_timer = 1
	await _tick(delta, displacement)
	return 1.0 - combat.accuracy


func _boundaries() -> void:
	var has_tolerance: bool = combat.get("tracking_parallel_tolerance_degrees") != null
	check(has_tolerance, "Player Combat exposes the shared parallel tolerance")
	if has_tolerance:
		await _prepare()
		combat.tracking_parallel_tolerance_degrees = 0
		combat.accuracy_recovery_timer = 1
		await _tick(0.1, Vector3(0.01, 0, -0.2))
		check(combat.accuracy < 0.8, "Zero tolerance uses the pure lateral projection")
	var near_edge: float = await _loss(0, Vector3(sin(deg_to_rad(5.01)), 0, -cos(deg_to_rad(5.01))), 0.2)
	var diagonal: float = await _loss(0, Vector3(1, 0, -1).normalized(), 0.2)
	check(near_edge > 0 and near_edge < diagonal * 0.01, "Penalty grows continuously beyond the parallel tolerance")
	# 同一横向分量增加径向速度，只能被平行容差减轻，不能因总跑速变大而增加损失。
	var lateral: float = await _loss(0, Vector3(0.2, 0, 0), 0.1)
	var rapid_approach: float = await _loss(0, Vector3(0.2, 0, 1.0), 0.1)
	check(rapid_approach > 0 and rapid_approach <= lateral, "Radial speed cannot select a stronger high-speed tracking penalty")
	await _prepare()
	combat.weapon.target_move_accuracy_loss_per_meter_slow = 0
	combat.weapon.target_move_accuracy_loss_per_meter_fast = 0
	await _tick(0.1, Vector3.RIGHT * 0.3)
	check(is_equal_approx(combat.accuracy, 0.85), "Zero tracking rates release recovery even during lateral motion")
	await _prepare()
	await _tick(0.1, Vector3.ZERO, Vector3.RIGHT * 0.1)
	check(is_equal_approx(combat.accuracy, 0.79), "Only the player's own movement penalty applies to a stationary target")
	await _prepare()
	combat.accuracy = 0.4
	await _tick(0.1, Vector3.FORWARD * 0.2, Vector3.RIGHT * 0.01)
	check(is_equal_approx(combat.accuracy, 0.45), "Player movement keeps its own recovery cap without a radial-target cap")
	await _prepare()
	combat.accuracy_recovery_timer = 0.4
	await _tick(0.1, Vector3.BACK * 0.2)
	check(is_equal_approx(combat.accuracy, 0.8) and is_equal_approx(combat.accuracy_recovery_timer, 0.3), "Radial motion does not skip existing recovery delay")
	await _prepare()
	target.rotation.y = PI
	await _tick(0.1, Vector3.ZERO)
	check(is_equal_approx(combat.accuracy, 0.85), "Rotating a stationary target does not count as movement")
	await _prepare()
	await _tick(0.1, Vector3.UP * 0.05)
	check(is_equal_approx(combat.accuracy, 0.85), "Vertical position changes do not count as ground-plane tracking")
	await _prepare()
	target.position.x += 0.2
	check(not combat._apply_target_movement_accuracy_penalty(0) and is_equal_approx(combat.accuracy, 0.8), "Zero delta updates the sample without inventing speed or loss")
	check(not combat._apply_target_movement_accuracy_penalty(0.1), "An invalid-time sample is not charged on the following frame")
	var results: Array[float] = []
	for fps in [30, 60, 120]:
		await _prepare(0, Vector3(-0.5, 0, -10))
		combat.accuracy = 1
		for frame in fps: await _tick(1.0 / fps, Vector3.RIGHT / fps)
		results.append(combat.accuracy)
	check(absf(results.max() - results.min()) < 0.0001 and results[0] < 1, "Equal motion at 30/60/120 steps per second has equal accumulated loss")


func _lifecycle() -> void:
	await _prepare()
	combat.accuracy_recovery_timer = 0.4
	paused = true
	await _tick(0.2, Vector3.RIGHT)
	check(is_equal_approx(combat.accuracy, 0.8) and is_equal_approx(combat.accuracy_recovery_timer, 0.4), "Pause freezes loss and recovery")
	paused = false
	await _tick(0.1, Vector3.ZERO)
	check(is_equal_approx(combat.accuracy, 0.8), "Resume does not charge target movement that occurred while paused")
	target.remove_from_group("combat_target")
	await _tick(0.1, Vector3.RIGHT)
	check(combat.locked_target == null and not combat.has_last_target_position, "Lost target clears the previous motion sample")
	target.add_to_group("combat_target")
	target.position = Vector3(-2, 0, -12)
	await physics_frame # 传送后的碰撞同步完成，再通过真实射线重新索敌。
	await _tick(0, Vector3.ZERO)
	check(combat.locked_target == target and is_equal_approx(combat.accuracy, 0.8), "Reacquiring a relocated target does not charge the lock gap")
	combat.equip_weapon(combat.weapon.duplicate(true))
	check(combat.locked_target == null and not combat.has_last_target_position, "Changing weapons clears old tracking samples")
	await _tick(0.1, Vector3.ZERO)
	player.set_dialogue_active(true)
	check(combat.locked_target == null and not combat.has_last_target_position, "Dialogue clears the target and motion history")
	player.set_dialogue_active(false)
	await _tick(0.1, Vector3.ZERO)
	player.health.debug_invincible = false
	player.receive_hit(player.health.health + 1)
	check(player.is_dead() and combat.locked_target == null and not combat.has_last_target_position, "Death clears the target and motion history")
