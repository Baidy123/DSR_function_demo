extends "res://tests/enemy/enemy_ally_navigation_test.gd"

## Real body execution contracts; autonomous route/cover choice is tested by
## the cooperation runtime suites, not by the prescribed movement below.
func _run() -> void:
	await _setup()
	await _reset(Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0))
	for actor in actors:
		var ai = actor.get_node("AI")
		Fixture.set_training_action(ai, &"cooperate", false)
		ai.set_physics_process(false)
		ai.context.update_evidence(STEP, false)
		check(not ai.context.cooperation_enabled() and actor.local_motion.spacing_enabled, "Basic spacing stays enabled when advanced cooperation training is disabled")
	var basic_settled := await _stand(150)
	check(actors[0].global_position.distance_to(actors[1].global_position) >= 1.08 and basic_settled.safe, "Advanced cooperation OFF still establishes real basic body clearance")
	check(basic_settled.late_motion < 0.02, "Basic spacing settles without requiring advanced tactical cooperation")
	await _reset(Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0))
	_set_spacing(false)
	var original := _positions()
	await _stand(45)
	check(_distance_moved(original) < 0.001, "Explicitly disabled body spacing leaves nearby stationary bodies at their original positions")
	_set_spacing(true)
	var targets := [actors[0].agent.target_position, actors[1].agent.target_position]
	var settled := await _stand(150)
	var separation: Vector3 = actors[0].global_position - actors[1].global_position
	check(Vector2(separation.x, separation.z).length() >= 1.08 and settled.safe, "Enabled spacing establishes real body clearance on open floor")
	var low: int = 0 if actors[0].get_instance_id() < actors[1].get_instance_id() else 1
	check(actors[low].global_position.distance_to(original[low]) < 0.001 and actors[1 - low].global_position.distance_to(original[1 - low]) > 0.2, "Stable instance priority adjusts one stationary participant instead of both oscillating")
	check(settled.late_motion < 0.02, "Established stationary spacing stays settled over the final second")
	check(actors[0].agent.target_position == targets[0] and actors[1].agent.target_position == targets[1], "Local spacing preserves the action-owned navigation destinations")
	await _reset(Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0))
	_set_spacing(true)
	actors[1 - low].configure_local_spacing(true, 0.0)
	original = _positions()
	settled = await _stand(100)
	check(settled.safe and actors[low].global_position.distance_to(original[low]) > 0.2 and actors[1 - low].global_position.distance_to(original[1 - low]) < 0.001, "A zero-margin peer does not veto the other body's enabled spacing policy")

	await _reset(Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0))
	# The normally responsible higher-ID body has no legal outward short point.
	# The partner on the open left still has room to establish clearance.
	if low != 0:
		actors[0].global_position = arena.to_global(Vector3(0.4, 0, 0))
		actors[1].global_position = arena.to_global(Vector3(-0.4, 0, 0))
	_wall(Vector3(0.85, 1, 0), Vector3(0.1, 2, 1.0))
	_wall(Vector3(0.6, 1, -0.46), Vector3(1.0, 2, 0.1))
	_wall(Vector3(0.6, 1, 0.46), Vector3(1.0, 2, 0.1))
	for frame in 3: await physics_frame
	_set_spacing(true)
	original = _positions()
	settled = await _stand(150)
	check(settled.safe and actors[low].global_position.distance_to(original[low]) > 0.2 and actors[0].global_position.distance_to(actors[1].global_position) >= 1.08, "When the priority participant has no legal room the open partner makes a bounded adjustment")
	check(settled.late_motion < 0.02, "Handing off a physically impossible spacing step still settles without repeated swapping")
	_clear_walls()
	await physics_frame

	await _reset(Vector3(-3, 0, -0.4), Vector3(-3, 0, 0.4))
	_set_spacing(true)
	var safe := true
	for frame in 120:
		await physics_frame
		for index in [frame % 2, 1 - frame % 2]:
			var before: Vector3 = actors[index].global_position
			actors[index].move_character(Vector3.RIGHT, STEP)
			safe = safe and _step_safe(actors[index], before)
		separation = actors[0].global_position - actors[1].global_position
		safe = safe and Vector2(separation.x, separation.z).length() >= 0.68
	check(safe and absf(actors[0].global_position.z - actors[1].global_position.z) >= 1.0, "Parallel movement creates lateral clearance without excess speed or body overlap")
	check(actors[0].global_position.x > arena.global_position.x and actors[1].global_position.x > arena.global_position.x, "Maintaining lateral spacing still advances both bodies along their requested direction")

	await _reset(Vector3(-3, 0, 0), Vector3(-1.8, 0, 0))
	_set_spacing(true)
	var minimum_follow_gap := INF
	for frame in 100:
		await physics_frame
		for index in [frame % 2, 1 - frame % 2]: actors[index].move_character(Vector3.RIGHT, STEP)
		minimum_follow_gap = minf(minimum_follow_gap, actors[0].global_position.distance_to(actors[1].global_position))
	check(minimum_follow_gap >= 1.08 and absf(actors[0].global_position.z - arena.global_position.z) < 0.01, "Same-direction following preserves extra clearance without needless sideways turns")

	await _reset(Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0))
	_set_spacing(true)
	_wall(Vector3(0, 1, 0), Vector3(0.08, 2, 4))
	await physics_frame
	original = _positions()
	await _stand(90)
	check(_distance_moved(original) < 0.001, "Nearby bodies separated by a solid wall do not invent shared floor space")
	_clear_walls()
	await physics_frame

	_make_corridor(false)
	await _reset(Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0))
	_set_spacing(true)
	var closed := await _travel(Vector3(3, 0, 0), Vector3(-3, 0, 0), 300)
	check(not closed.first_arrived and not closed.second_arrived and closed.safe and closed.maximum_side < 0.2, "An impossible narrow crossing queues or yields finitely without crossing walls or bodies")
	check(closed.late_motion < 0.35, "A blocked narrow crossing settles instead of continually squeezing a stationary ally")
	_clear_walls()
	await physics_frame

	await _reset(Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0))
	_set_spacing(true)
	for actor in actors: actor.move_character(Vector3.ZERO, STEP)
	var pending := actors.any(func(actor): return actor.local_motion._point_kind == &"spacing")
	_set_spacing(false)
	original = _positions()
	await _stand(30)
	check(pending and _distance_moved(original) < 0.001, "Explicitly disabling body spacing cancels an already requested spacing adjustment")

	await _reset(Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0))
	_set_spacing(true)
	var immobile = actors[1 - low]
	check(immobile.begin_melee(0.5), "Spacing interruption control enters a real melee windup")
	var fixed_position: Vector3 = immobile.global_position
	await _stand(12)
	check(immobile.global_position.distance_to(fixed_position) < 0.001, "Spacing cannot bypass the body's melee movement prohibition")
	immobile.cancel_melee()

	await _reset(Vector3(-3, 0, 0), Vector3(7, 0, 7))
	_set_spacing(true)
	var before: Vector3 = actors[0].global_position
	actors[0].move_character(Vector3.RIGHT, STEP)
	check(absf(actors[0].global_position.x - before.x - actors[0].move_speed * STEP) < 0.001 and absf(actors[0].global_position.z - before.z) < 0.001, "A lone nearby participant retains the original direction and speed")
	print("ALLY SPACING: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _set_spacing(enabled: bool) -> void:
	for actor in actors:
		actor.configure_local_spacing(enabled, 0.45)
		check(actor.local_motion.spacing_enabled == enabled, "The explicit body spacing interface updates its local policy")

func _positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for actor in actors: result.append(actor.global_position)
	return result

func _distance_moved(before: Array[Vector3]) -> float:
	var total := 0.0
	for index in actors.size(): total += actors[index].global_position.distance_to(before[index])
	return total

func _step_safe(actor, before: Vector3) -> bool:
	var moved: Vector3 = actor.global_position - before
	return Vector2(moved.x, moved.z).length() <= actor.move_speed * STEP + 0.005 and absf(actor.global_position.y) < 0.05

func _stand(frames: int) -> Dictionary:
	var result := {"safe": true, "late_motion": 0.0}
	for frame in frames:
		await physics_frame
		for index in [frame % 2, 1 - frame % 2]:
			var before: Vector3 = actors[index].global_position
			actors[index].move_character(Vector3.ZERO, STEP)
			result.safe = result.safe and _step_safe(actors[index], before)
			if frame >= frames - 60: result.late_motion += actors[index].global_position.distance_to(before)
		var apart: Vector3 = actors[0].global_position - actors[1].global_position
		result.safe = result.safe and Vector2(apart.x, apart.z).length() >= 0.68
	return result
