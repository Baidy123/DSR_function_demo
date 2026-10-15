extends "res://tests/enemy/enemy_cover_inspection_test.gd"

## Real perception, ordinary Utility, action ticks and body collision drive this
## fixture. No selected action, assignment, readiness or completed fact is forced.
const TrainingFixture = preload("res://tests/enemy/enemy_fire_fixture.gd")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			await _coordinated_inspection(int(argument.trim_prefix("--count=")))
			print("TEAM INSPECTION RUNTIME: %d/%d passed" % [checks - failures, checks])
			quit(1 if failures else 0)
			return
	await _frozen_observation_lifetime()
	if OS.get_cmdline_user_args().has("--source-only"):
		print("TEAM OBSERVATION MEMORY: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	await _coordinated_inspection(2)
	await _coordinated_inspection(3)
	print("TEAM INSPECTION RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _frozen_observation_lifetime() -> void:
	await _setup(true)
	cover.collision_layer = 0
	for actor in actors:
		TrainingFixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
		actor.get_node("AI").set_physics_process(false)
		actor.set_physics_process(false)
	actors[1].global_position = arena.to_global(Vector3(6, 0, 4))
	actors[1].look_at(player.global_position)
	for frame in 4: await _tick()
	check(actors[0].get_node("AI").context.sees_player, "Planning-memory source begins with a real personal observation")
	player.global_position = arena.to_global(Vector3(-6, 0, -4))
	# The receiver stayed behind the opaque screen throughout the observation.
	# Only it updates after hiding, so no observer's new loss event masks memory.
	for frame in 3:
		await physics_frame
		actors[1].get_node("AI")._physics_process(STEP)
	var context = actors[1].get_node("AI").context
	var source: Dictionary = context.coordination_source(context.cooperation_target_id())
	check(not context.sees_player and not context.has_visual_memory and not context.fresh_shared_contact().is_empty() and source.get("source") == &"observation_memory", "A real shared observation supplies frozen planning memory without inventing personal sight or a loss event")
	print("TEAM OBSERVATION SOURCE ", JSON.stringify(source))
	if not source.is_empty():
		for index in 10:
			for actor in actors: actor.get_node("AI").context._publish_coordination_evidence()
			context.coordination_source(context.cooperation_target_id())
		var repeated: Dictionary = context.coordination_source(context.cooperation_target_id())
		check(repeated.captured_at == source.captured_at and repeated.valid_until == source.valid_until, "Repeated publication and source reads do not renew the original captured observation")
		for actor in actors: actor.get_node("AI").context.evidence_elapsed_seconds += 5.5
		arena.cooperation.advance(5.5)
		var retained: Dictionary = context.coordination_source(context.cooperation_target_id())
		check(context.fresh_shared_contact().is_empty() and not retained.is_empty() and retained.evidence_id == source.evidence_id and retained.position == source.position and retained.valid_until == source.valid_until, "After the precise five-second report expires, planning retains only the same frozen observation and deadline")
		player.global_position = arena.to_global(Vector3(-7, 0, 4))
		for actor in actors: actor.get_node("AI").context._publish_coordination_evidence()
		check(context.coordination_source(context.cooperation_target_id()) == retained and not context.sees_player, "Moving the hidden player cannot change planning position, identity, age or personal visibility")
		var until_expiry: float = source.valid_until - arena.cooperation.elapsed + 0.01
		for actor in actors: actor.get_node("AI").context.evidence_elapsed_seconds += until_expiry
		arena.cooperation.advance(until_expiry)
		context._publish_coordination_evidence()
		check(context.coordination_source(context.cooperation_target_id()).is_empty(), "Planning memory expires at its original deadline and old publications cannot resurrect it")
	scene.queue_free()
	await physics_frame

func _coordinated_inspection(count: int) -> void:
	seed(20261011)
	await _setup(true)
	if count == 3:
		var third = load("res://scenes/enemy/enemy.tscn").instantiate()
		third.position = Vector3(2.8, 0, 3.5)
		arena.add_child(third)
		third.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
		third.equip_weapon(WeaponData.new())
		third.get_node("AI").training.profile = actors[0].get_node("AI").training.profile.duplicate(true)
		third.get_node("AI").refresh_configuration(true)
		third.get_node("AI").set_physics_process(false)
		third.look_at(player.global_position)
		actors.append(third)
	for actor in actors:
		TrainingFixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
		actor.get_node("AI").set_physics_process(false)
	for frame in 12: await physics_frame
	for frame in 4: await _tick()
	check(actors.all(func(actor): return actor.get_node("AI").context.sees_player), "%d actors actually see the standing player before investigation" % count)
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	check(player.is_crouching() and actors.all(func(actor): return not actor.get_node("AI").context.sees_player), "%d actors become blind through real crouched cover occlusion" % count)
	var evidence: Dictionary = actors[0].get_node("AI").context.cover_inspection_evidence()
	check(not evidence.is_empty(), "%d-actor fixture produces a real frozen cover clue" % count)
	if evidence.is_empty():
		scene.queue_free()
		await physics_frame
		return
	var known: Vector3 = evidence.position
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var initial: Array[Vector3] = []
	for actor in actors: initial.append(actor.global_position)
	var assigned: Dictionary = {}
	var observations: Dictionary = {}
	var executed_roles: Dictionary = {}
	var simultaneous_roles_valid := true
	var third_motion := 0.0
	var unassigned_active := false
	var hidden_unchanged := true
	var no_inspection_fire := true
	var trace: Array = []
	var accepted_deadlines: Dictionary = {}
	var deadlines_fixed := true
	var min_separation := INF
	for frame in 960:
		await physics_frame
		for index in count:
			actors[index].get_node("AI")._physics_process(STEP)
			_record_inspection(observations, actors[index], frame, known)
		var current_roles: Array = []
		for index in count:
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var context = ai.context
			var search = ai.actions[&"search"]
			var task: Dictionary = context.coordination_assignment()
			if task.get("role", &"") in [&"inspect_left", &"inspect_right"]:
				assigned[index] = task.role
				current_roles.append(task.role)
				if not accepted_deadlines.has(task.assignment_id): accepted_deadlines[task.assignment_id] = task.expires_at
				deadlines_fixed = deadlines_fixed and accepted_deadlines[task.assignment_id] == task.expires_at
				if task.get("accepted", false) and not search._inspection_route.is_empty():
					if search._inspection_phase == search.InspectionPhase.CHECK:
						executed_roles[index] = task.role
			elif count == 3 and actors.filter(func(other): return other.get_node("AI").context.coordination_assignment().get("role", &"") in [&"inspect_left", &"inspect_right"]).size() == 2:
				third_motion = maxf(third_motion, actor.global_position.distance_to(initial[index]))
				unassigned_active = unassigned_active or (not ai.utility_current.is_empty() and search._inspection_phase == search.InspectionPhase.NONE)
			if search._inspection_phase != search.InspectionPhase.NONE:
				no_inspection_fire = no_inspection_fire and context.fire.request.is_empty()
			var clue: Dictionary = context.cover_inspection_evidence()
			hidden_unchanged = hidden_unchanged and (clue.is_empty() or clue.position.is_equal_approx(known))
			if frame % 60 == 0:
				trace.append({"frame": frame, "actor": index, "action": ai.utility_current.get("id", &""), "role": task.get("role", &""), "phase": task.get("phase", &""), "local_phase": search._inspection_phase, "position": actor.global_position, "offers": search._inspection_offers.size()})
		for left in count:
			for right in range(left + 1, count): min_separation = minf(min_separation, actors[left].global_position.distance_to(actors[right].global_position))
		simultaneous_roles_valid = simultaneous_roles_valid and current_roles.size() <= 2 and (current_roles.size() != 2 or current_roles[0] != current_roles[1])
		if observations.values().any(func(record): return record.completed.size() == 2) and current_roles.is_empty() and (count == 2 or third_motion > 0.5): break
	var roles: Array = executed_roles.values()
	check(simultaneous_roles_valid and roles.has(&"inspect_left") and roles.has(&"inspect_right"), "%d actors autonomously execute complementary roles with at most one current owner per end, including legal reassignment" % count)
	var complete_runs: Array = observations.values().filter(func(record): return record.completed.size() == 2)
	check(not observations.is_empty() and observations.values()[0].completed.size() == 2, "%d-actor original inspection plan completes both real reports despite a passing member, without canceling and retrying" % count)
	check(complete_runs.any(func(record): return record.checked.size() == 2 and record.completed.keys().all(func(role): return record.checked.has(role))), "%d-actor inspectors actually reach separate entries and observe the frozen ground from both ends" % count)
	check(not complete_runs.is_empty() and actors.all(func(actor): return actor.get_node("AI").context.coordination_assignment().is_empty()), "%d-actor real observation completes both reports and releases the shared task" % count)
	var synchronized := false
	var every_released_pair := true
	for record in observations.values():
		for starts: Dictionary in record.starts.values():
			if starts.size() != 2: continue
			var together: bool = abs(int(starts.values()[0]) - int(starts.values()[1])) <= 1
			every_released_pair = every_released_pair and together
			synchronized = synchronized or (record.completed.size() == 2 and together)
	synchronized = synchronized and every_released_pair
	check(synchronized, "%d-actor inspectors physically start the released check segment within one update" % count)
	check(deadlines_fixed and hidden_unchanged and no_inspection_fire and min_separation >= 0.69, "%d-actor execution preserves fixed deadlines, hidden evidence, nonfiring inspection and real body separation" % count)
	if count == 3:
		check(unassigned_active and third_motion > 0.5, "The third blind member remains active and actually investigates without entering an unassigned inspection wait")
	print("TEAM INSPECTION TRACE count=", count, " assigned=", assigned, " observations=", observations, " third_motion=", third_motion, " ", JSON.stringify(trace))
	scene.queue_free()
	await physics_frame

func _record_inspection(observations: Dictionary, actor, frame: int, known: Vector3) -> void:
	# Observe each real execution before another member can finish and retire
	# the shared plan. Reassignment and a later plan have distinct identities.
	var context = actor.get_node("AI").context
	var search = actor.get_node("AI").actions[&"search"]
	var task: Dictionary = context.coordination_assignment()
	if task.get("role", &"") not in [&"inspect_left", &"inspect_right"] or not task.get("accepted", false) or search._inspection_route.is_empty(): return
	if not observations.has(task.plan_id): observations[task.plan_id] = {"arrived": {}, "checked": {}, "completed": {}, "starts": {}}
	var record: Dictionary = observations[task.plan_id]
	if actor.global_position.distance_to(search._inspection_route.entry) <= 0.3: record.arrived[task.assignment_id] = true
	if search._inspection_phase == search.InspectionPhase.CHECK:
		if not record.starts.has(task.phase_id): record.starts[task.phase_id] = {}
		if not record.starts[task.phase_id].has(task.role): record.starts[task.phase_id][task.role] = frame
	if record.arrived.has(task.assignment_id) and actor.global_position.distance_to(search._inspection_route.peek) <= 0.3 and context.perception.can_observe_position(known): record.checked[task.role] = true
	if task.get("complete", false) and context._coordination_execution_completed and record.checked.has(task.role): record.completed[task.role] = true
