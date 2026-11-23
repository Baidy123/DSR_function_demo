extends "res://tests/enemy/enemy_ally_navigation_test.gd"

## Multi-body execution with real CharacterBody3D collisions and original speeds.
## This verifies the body spacing/yield contract, not autonomous tactical choice.
func _run() -> void:
	await _setup()
	for count in [3, 6]:
		await _cluster(count)
		var initial_gap := _minimum_separation()
		var safe := true
		var late_motion := 0.0
		for frame in 300:
			await physics_frame
			for offset in actors.size():
				var actor = actors[(frame + offset) % actors.size()]
				var before: Vector3 = actor.global_position
				actor.move_character(Vector3.ZERO, STEP)
				safe = safe and _step_safe(actor, before)
				if frame >= 240: late_motion += actor.global_position.distance_to(before)
			safe = safe and _minimum_separation() >= 0.68
		var final_gap := _minimum_separation()
		check(initial_gap < 0.85 and final_gap >= 1.06 and safe, "%d real bodies spread a compact formation while respecting floor, speed and collision bounds" % count)
		check(late_motion < 0.05, "%d real bodies retain their established spacing instead of oscillating" % count)
		print("SPACING CLUSTER count=", count, " initial=", initial_gap, " final=", final_gap, " late_motion=", late_motion)
		await _pass_cluster(count)
	print("ALLY SPACING RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _cluster(count: int) -> void:
	while actors.size() < count:
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		actor.position = Vector3(4, 0, 4)
		arena.add_child(actor)
		Fixture.configure_timing(actor)
		actor.get_node("AI").set_physics_process(false)
		actor.debug_shooting = false
		actors.append(actor)
	var positions: Array[Vector3] = [Vector3(-0.38, 0, -0.22), Vector3(0.38, 0, -0.22), Vector3(0, 0, 0.44)]
	if count == 6:
		positions.clear()
		for row in 2:
			for column in 3: positions.append(Vector3((column - 1) * 0.78, 0, (row - 0.5) * 0.78))
	for index in actors.size():
		var actor = actors[index]
		actor.reset_target()
		actor.global_position = arena.to_global(positions[index])
		actor.velocity = Vector3.ZERO
		actor.agent.target_position = actor.global_position
		Fixture.set_training_action(actor.get_node("AI"), &"cooperate", false)
		actor.get_node("AI").set_physics_process(false)
	for frame in 4: await physics_frame
	for actor in actors:
		actor.get_node("AI").context.update_evidence(STEP, false)
		check(not actor.get_node("AI").context.cooperation_enabled() and actor.local_motion.spacing_enabled, "%d-body fixture receives default basic spacing with advanced cooperation OFF" % count)

func _pass_cluster(count: int) -> void:
	var mover = actors[-1]
	var front = actors[0]
	for actor in actors:
		if actor != mover and actor.global_position.x < front.global_position.x: front = actor
	var start: Vector3 = front.global_position - Vector3.RIGHT * 1.2
	var goal: Vector3 = front.global_position + Vector3.RIGHT * 4.2
	mover.clear_local_movement()
	mover.global_position = start
	mover.velocity = Vector3.ZERO
	for frame in 4: await physics_frame
	var safe := true
	var yielded := false
	var arrived := false
	var late_motion := 0.0
	for frame in 360:
		await physics_frame
		for offset in actors.size():
			var actor = actors[(frame + offset) % actors.size()]
			var before: Vector3 = actor.global_position
			var direction := Vector3.ZERO
			if actor == mover:
				direction = goal - actor.global_position
				direction.y = 0.0
				direction = direction.normalized() * minf(1.0, direction.length() / maxf(0.001, actor.move_speed * STEP))
			actor.move_character(direction, STEP)
			safe = safe and _step_safe(actor, before)
			yielded = yielded or actor.local_motion._point_kind in [&"pass", &"yield"]
			if frame >= 300: late_motion += actor.global_position.distance_to(before)
		safe = safe and _minimum_separation() >= 0.68
		arrived = arrived or mover.global_position.distance_to(goal) < 0.12
	check(arrived and yielded and safe, "%d-body formation lets a real approaching ally pass using finite collision-safe local corrections" % count)
	check(late_motion < 0.1, "%d-body formation settles again after the passer reaches its original goal" % count)
	print("SPACING PASS count=", count, " arrived=", arrived, " yielded=", yielded, " safe=", safe, " late_motion=", late_motion, " remaining=", mover.global_position.distance_to(goal))

func _minimum_separation() -> float:
	var distance := INF
	for first in actors.size():
		for second in range(first + 1, actors.size()):
			var offset: Vector3 = actors[first].global_position - actors[second].global_position
			distance = minf(distance, Vector2(offset.x, offset.z).length())
	return distance

func _step_safe(actor, before: Vector3) -> bool:
	var moved: Vector3 = actor.global_position - before
	return Vector2(moved.x, moved.z).length() <= actor.move_speed * STEP + 0.005 and absf(actor.global_position.y) < 0.05
