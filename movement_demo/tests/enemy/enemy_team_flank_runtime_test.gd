extends "res://tests/enemy/enemy_cooperation_flank_runtime_test.gd"

## The inherited real floor/navigation fixture retains normal competing actions.
## Only the ordinary AI loop selects, accepts, starts and completes team work.
func _run() -> void:
	var counts: Array = [2, 3, 6]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="): counts = [int(argument.trim_prefix("--count="))]
	for count: int in counts: await _team_maneuver(count)
	print("TEAM FLANK RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _team_maneuver(count: int) -> void:
	var f: Dictionary = await _fixture(count, true)
	var actors: Array = f.actors
	# Give this completion fixture enough ammunition for initial contact plus the
	# whole route. Empty-magazine cancellation is tested separately by sync runtime.
	for actor in actors:
		var weapon: WeaponData = actor.weapon.duplicate(true)
		weapon.magazine_capacity = 60
		actor.equip_weapon(weapon)
	var anchor: Vector3 = f.player.global_position
	var last_positions: Array[Vector3] = []
	var last_shots: Array[int] = []
	for actor in actors:
		last_positions.append(actor.global_position)
		last_shots.append(actor.shot_count)
	var accepted_flanks: Dictionary = {}
	var accepted_fronts: Dictionary = {}
	var crossed: Dictionary = {}
	var completed: Dictionary = {}
	var deadlines: Dictionary = {}
	var fixed_deadlines := true
	var quota_valid := true
	var minimum_radius := INF
	var minimum_front := count
	var protected_motion := 0.0
	var front_overlap_shots := 0
	var released_movement := false
	var trace: Array = []
	var previous_assignments: Dictionary = {}
	for frame in 1080:
		await physics_frame
		for actor in actors: actor.get_node("AI")._physics_process(STEP)
		var active_flanks := 0
		var physical_fronts := 0
		var flank_moving := false
		var ready_front := false
		for index in count:
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			var role: StringName = task.get("role", &"")
			var previous: Dictionary = previous_assignments.get(index, {})
			if not previous.is_empty() and task.get("assignment_id", 0) != previous.get("assignment_id", 0):
				trace.append({"event": "assignment_exit", "frame": frame, "actor": index, "previous": previous, "position": actor.global_position, "action": ai.utility_current.get("id", &""), "ammo": actor.ammo.magazine_rounds})
			previous_assignments[index] = {"assignment_id": task.assignment_id, "role": role, "selected_position": task.get("selected_position", Vector3.INF), "expires_at": task.expires_at, "phase": task.phase, "complete": task.get("complete", false)} if not task.is_empty() else {}
			if actor.global_position.x > anchor.x + OPPOSITE_MARGIN: physical_fronts += 1
			if not task.is_empty():
				if not deadlines.has(task.assignment_id): deadlines[task.assignment_id] = task.expires_at
				fixed_deadlines = fixed_deadlines and deadlines[task.assignment_id] == task.expires_at
			if role == &"flank":
				active_flanks += 1
				if task.accepted:
					accepted_flanks[index] = true
					var displacement: float = actor.global_position.distance_to(last_positions[index])
					if displacement > 0.002 and _flanking(ai):
						flank_moving = true
						released_movement = released_movement or (task.phase == &"executing" and task.release_at >= 0.0)
						minimum_radius = minf(minimum_radius, Vector2(actor.global_position.x - anchor.x, actor.global_position.z - anchor.z).length())
					if actor.global_position.x < anchor.x - OPPOSITE_MARGIN: crossed[index] = true
					if task.get("complete", false) and ai.context._coordination_execution_completed: completed[index] = true
			elif role == &"front_support" and task.accepted:
				accepted_fronts[index] = true
				var actual: Dictionary = ai.actions[&"cooperate"]._own_actual_support()
				ready_front = ready_front or (actual.ready and actual.seconds > 0.0 and actor.global_position.x > anchor.x + OPPOSITE_MARGIN)
			if frame % 60 == 0:
				trace.append({"frame": frame, "actor": index, "action": ai.utility_current.get("id", &""), "plan": ai.utility_current.get("plan", &""), "role": role, "team_phase": task.get("phase", &""), "position": actor.global_position, "offers": ai.actions[&"cooperate"]._coordination_offers.size(), "source": ai.context.coordination_source(ai.context.cooperation_target_id()), "actual": ai.actions[&"cooperate"]._own_actual_support()})
		quota_valid = quota_valid and active_flanks <= count / 2
		if active_flanks > 0: minimum_front = mini(minimum_front, physical_fronts)
		if flank_moving and ready_front: protected_motion += STEP
		for index in count:
			var actor = actors[index]
			var task: Dictionary = actor.get_node("AI").context.coordination_assignment()
			if flank_moving and task.get("role", &"") == &"front_support": front_overlap_shots += maxi(0, actor.shot_count - last_shots[index])
			last_positions[index] = actor.global_position
			last_shots[index] = actor.shot_count
		if not completed.is_empty() and actors.all(func(actor): return actor.get_node("AI").context.coordination_assignment().is_empty()): break
	check(not accepted_flanks.is_empty() and not accepted_fronts.is_empty(), "%d actors autonomously accept complementary flank and front-support assignments" % count)
	check(not crossed.is_empty() and released_movement and minimum_radius >= TARGET_CLEARANCE - 0.1, "%d actors physically follow the released route to the opposite side without crossing the target" % count)
	check(protected_motion > 0.1 and front_overlap_shots > 0 and minimum_front > 0, "%d-actor maneuver overlaps real front support and actual shots while preserving a physical front" % count)
	check(quota_valid and fixed_deadlines, "%d-actor assignments retain the half-team quota and original fixed deadlines" % count)
	check(not completed.is_empty(), "%d-actor real flank execution reports completion at its destination" % count)
	print("TEAM FLANK TRACE count=", count, " flanks=", accepted_flanks, " fronts=", accepted_fronts, " crossed=", crossed, " completed=", completed, " overlap_seconds=", protected_motion, " overlap_shots=", front_overlap_shots, " radius=", minimum_radius, " ", JSON.stringify(trace))
	f.scene.queue_free()
	await physics_frame
