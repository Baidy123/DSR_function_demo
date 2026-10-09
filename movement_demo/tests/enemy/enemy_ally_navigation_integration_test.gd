extends "res://tests/enemy/enemy_ally_navigation_test.gd"

func _run() -> void:
	await _setup()
	await _shooting_yield()
	_clear_walls()
	var player = scene.get_node("Player")
	player.global_position = arena.to_global(Vector3(6, 0, 7))
	await _reset(Vector3(-7.6, 0, -3), Vector3(-7.6, 0, 0))
	var boundary_safe := true
	var original_targets := [actors[0].agent.target_position, actors[1].agent.target_position]
	for frame in 360:
		await physics_frame
		_move_to(actors[0], arena.to_global(Vector3(-7.6, 0, 3)))
		actors[1].move_character(Vector3.ZERO, STEP)
		for actor in actors:
			var projected: Vector3 = NavigationServer3D.region_get_closest_point(arena.get_node("NavigationRegion3D").get_rid(), actor.global_position)
			boundary_safe = boundary_safe and Vector2(projected.x - actor.global_position.x, projected.z - actor.global_position.z).length() <= 0.05
	print("ALLY BOUNDARY safe=", boundary_safe, " positions=", actors[0].global_position, ", ", actors[1].global_position)
	check(boundary_safe and actors[0].global_position.distance_to(arena.to_global(Vector3(-7.6, 0, 3))) < 0.12, "导航边缘拒绝网格外侧移，使用合法一侧仍到达原目标")
	check(actors[0].agent.target_position == original_targets[0] and actors[1].agent.target_position == original_targets[1], "身体让路全程不改写动作的 NavigationAgent 目的地")
	await _reopened_passage()

	await _reset(Vector3(-3, 0, 0), Vector3(0, 0, 0))
	actors[1].receive_hit(actors[1].max_health)
	for frame in 20:
		await physics_frame
		actors[0].move_character(Vector3.RIGHT, STEP)
	await _reset(Vector3(-3, 0, 0), Vector3(0, 0, 0))
	for actor in actors: actor.get_node("AI").context.update_evidence(STEP, false)
	var revived := await _travel(Vector3(3, 0, 0), Vector3.INF, 360)
	check(revived.first_arrived and revived.safe and revived.first_side > 0.25, "死亡成员复活并重新发布真实状态后仍能参与身体避让")
	await _body_interruptions()

	# Obtain a real pending correction, then detach the neighbor through the
	# public environment lifecycle rather than forging a helper state.
	await _reset(Vector3(-1.1, 0, 0), Vector3(0, 0, 0))
	for frame in 4:
		await physics_frame
		actors[1].move_character(Vector3.ZERO, STEP)
		actors[0].move_character(Vector3.RIGHT, STEP)
	actors[1].get_node("AI").context.detach_environment()
	actors[1].global_position = arena.to_global(Vector3(7, 0, 7))
	await physics_frame
	var before: Vector3 = actors[0].global_position
	actors[0].move_character(Vector3.RIGHT, STEP)
	var change: Vector3 = actors[0].global_position - before
	check(absf(change.z) < 0.001 and absf(change.x - actors[0].move_speed * STEP) < 0.001, "友军离区后立即清除旧绕行，单人原方向与原速度恢复")
	print("ALLY NAVIGATION INTEGRATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _shooting_yield() -> void:
	# Only the approach is narrow. The shooter's side pocket has a clear shot
	# toward +X, so a wall cannot accidentally satisfy the moving-fire gate.
	_wall(Vector3(0, 1, -0.7), Vector3(8, 2, 0.2))
	_wall(Vector3(-2.45, 1, 0.7), Vector3(3.1, 2, 0.2))
	await _reset(Vector3(-3, 0, 0), Vector3(0, 0, 0))
	var player = scene.get_node("Player")
	player.global_position = arena.to_global(Vector3(5, 0, 0))
	player.get_node("Health").debug_invincible = true
	var shooter = actors[1]
	var ai = shooter.get_node("AI")
	shooter.weapon.shot_interval = 0.05
	shooter.weapon.magazine_capacity = 100
	shooter.ammo.magazine_rounds = 100
	shooter.aim_turn_speed_degrees = 3600.0
	ai.training.profile.set_setting(&"tactics", &"fire_while_moving", false)
	ai.training.profile.set_setting(&"tactics", &"fire_reaction_seconds", 0.0)
	ai.training.profile.set_setting(&"tactics", &"burst_shot_count", 100)
	shooter.look_at(player.global_position)
	for frame in 60:
		await physics_frame
		ai._physics_process(STEP)
	check(ai.utility_current.get("id") == &"engage" and ai.utility_current.get("destination", {}).is_empty() and shooter.shot_count > 0, "真实 Utility 自主选择站定接敌并已实际开枪")
	var moved_frames := 0
	var local_yield_frames := 0
	var clear_moving_frames := 0
	var stopped_fire := true
	var published_motion := true
	var finite_motion := true
	var stage_shots: int = shooter.shot_count
	var target: Vector3 = arena.to_global(Vector3(3, 0, 0))
	for frame in 300:
		await physics_frame
		_move_to(actors[0], target)
		var before: Vector3 = shooter.global_position
		var shots: int = shooter.shot_count
		ai._physics_process(STEP)
		var moved: Vector3 = shooter.global_position - before
		if Vector2(moved.x, moved.z).length() > 0.001:
			moved_frames += 1
			if ai.utility_current.get("id") == &"engage" and ai.utility_current.get("destination", {}).is_empty(): local_yield_frames += 1
			stopped_fire = stopped_fire and shooter.shot_count == shots
			finite_motion = finite_motion and Vector2(moved.x, moved.z).length() <= shooter.move_speed * STEP + 0.005
			var aim: Vector3 = player.get_torso_position() - shooter.get_shot_origin()
			if ai.context.fire.has_clear_firing_lane(shooter.get_shot_origin(), aim, aim.length()): clear_moving_frames += 1
			var found := false
			for member in ai.context.cooperation_snapshot().members:
				if member.id == shooter.get_instance_id():
					found = true
					published_motion = published_motion and member.moving and not member.ready
			published_motion = published_motion and found and not shooter.get_local_movement_velocity().is_zero_approx()
	check(local_yield_frames >= 10 and actors[0].global_position.distance_to(target) < 0.12 and finite_motion, "自主站定射击者真实让行，通行者继续抵达原目标且不加速")
	check(clear_moving_frames >= 10 and stopped_fire, "侧移期间射界仍清楚，禁止移动开火时没有新增射击")
	check(published_motion, "协作快照公布真实侧移 moving，不能把让行者计作站定掩护")
	check(shooter.shot_count > stage_shots, "让行前后可正常继续射击，不会永久取消接敌行为")
	print("ALLY FIRING yield_frames=", local_yield_frames, " moving_frames=", moved_frames, " clear_frames=", clear_moving_frames, " mover=", actors[0].global_position, " shooter=", shooter.global_position)

func _move_to(actor, target: Vector3) -> void:
	var direction: Vector3 = target - actor.global_position
	direction.y = 0.0
	var distance := direction.length()
	actor.move_character(direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * STEP)), STEP)

func _pending_correction() -> void:
	await _reset(Vector3(-1.1, 0, 0), Vector3(0, 0, 0))
	for frame in 5:
		await physics_frame
		actors[1].move_character(Vector3.ZERO, STEP)
		actors[0].move_character(Vector3.RIGHT, STEP)
	check(absf(actors[0].global_position.z) > 0.05, "互斥场景先形成真实尚未完成的侧让")

func _reopened_passage() -> void:
	_make_corridor(false)
	await _reset(Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0))
	var closed := await _travel(Vector3(3, 0, 0), Vector3(-3, 0, 0), 120)
	check(not closed.first_arrived and not closed.second_arrived and closed.safe, "恢复对照先在真实无出口通道中有限停步")
	var opened = walls.pop_back()
	opened.queue_free()
	await physics_frame
	var reopened := await _travel(Vector3(3, 0, 0), Vector3(-3, 0, 0), 360)
	check(reopened.first_arrived and reopened.second_arrived and reopened.safe, "通道一侧真实开放后会重查合法让行，不永久等待旧失败状态")
	_clear_walls()
	await physics_frame

func _body_interruptions() -> void:
	await _pending_correction()
	var actor = actors[0]
	var before: Vector3 = actor.global_position
	actor.receive_melee_hit(0.0, before + Vector3.RIGHT, 0.4, 0.2)
	var push_only := true
	for frame in 60:
		await physics_frame
		actor.move_character(Vector3.ZERO, STEP)
		actors[1].move_character(Vector3.ZERO, STEP)
		push_only = push_only and absf(actor.global_position.z - before.z) < 0.001 and actor.get_local_movement_velocity().is_zero_approx()
	check(push_only and actor.global_position.x < before.x - 0.25, "真实击退沿外力方向执行，结束后不恢复旧侧让或混入自主速度")

	await _pending_correction()
	actors[1].global_position = arena.to_global(Vector3(7, 0, 7))
	var cover = load("res://scenes/world/low_cover.tscn").instantiate()
	scene.add_child(cover)
	cover.global_position = actor.global_position + Vector3(0.9, 0.55, 0.0)
	cover.rotation.y = PI * 0.5
	await physics_frame
	var plan: Dictionary = preload("res://scripts/world/low_cover_geometry.gd").query_vault_at(actor, cover, actor.global_position, Vector3.RIGHT, 0.8, false)
	var started: bool = actor.begin_vault(plan)
	check(started, "已有侧让时身体通过真实低墙弧线预检进入翻越")
	var vault_axis_z: float = actor.global_position.z
	var stayed_on_arc := true
	for frame in 150:
		await physics_frame
		actor.move_character(Vector3.ZERO, STEP)
		actors[1].move_character(Vector3.ZERO, STEP)
		stayed_on_arc = stayed_on_arc and absf(actor.global_position.z - vault_axis_z) < 0.001 and actor.get_local_movement_velocity().is_zero_approx()
	check(started and stayed_on_arc and not actor.is_vaulting() and actor.global_position.distance_to(plan.get("exit", Vector3.INF)) < 0.12, "翻越和落地完全遵守原弧线，旧让行不会在落地后拉回身体")
	cover.queue_free()
	await physics_frame
