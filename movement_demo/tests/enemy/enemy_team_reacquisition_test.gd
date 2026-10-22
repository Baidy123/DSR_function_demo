extends "res://tests/enemy/enemy_cover_inspection_test.gd"

const TrainingFixture = preload("res://tests/enemy/enemy_fire_fixture.gd")

func _run() -> void:
	await _case(false)
	await _case(true)
	print("TEAM REACQUISITION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _case(explicit_squad: bool) -> void:
	print("REACQUISITION EXPLICIT SQUAD ", explicit_squad)
	seed(20261011)
	await _setup(false)
	var third = load("res://scenes/enemy/enemy.tscn").instantiate()
	third.weapon = WeaponData.new()
	third.position = Vector3(2.8, 0, 3.5)
	arena.add_child(third)
	third.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	third.get_node("AI").training.profile = actors[0].get_node("AI").training.profile.duplicate(true)
	actors.append(third)
	for actor in actors:
		actor.get_node("AI").training.profile.set_setting(&"perception", &"close_cover_intelligence_enabled", false)
		TrainingFixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
		actor.get_node("AI").set_physics_process(false)
		actor.look_at(player.global_position)
	if explicit_squad: TrainingFixture.attach_squad(arena, actors, 2)
	for frame in 12: await physics_frame
	for frame in 4: await _tick()
	check(actors.all(func(actor): return actor.get_node("AI").context.sees_player), "Three enemies really see the standing player")
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	check(actors.all(func(actor): return not actor.get_node("AI").context.sees_player), "Crouching really occludes the unchanged player position")
	# Keep the target out of sight while the actors' original committed movement
	# finishes. Restore the identical reported position for the handoff below.
	var known: Vector3 = player.global_position
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var assigned: Array = []
	for frame in 600:
		await _tick()
		assigned = actors.filter(func(actor): return actor.get_node("AI").context.coordination_assignment().get("role") in [&"inspect_left", &"inspect_right"] and not actor.get_node("AI").actions[&"search"]._inspection_assignment.is_empty())
		if assigned.size() == 2: break
	check(assigned.size() == 2, "Ordinary Utility accepts a real pair of endpoint assignments")
	if assigned.size() == 2:
		for actor in actors: actor.set_physics_process(false)
		var observer = actors.filter(func(actor): return not assigned.has(actor))[0]
		if explicit_squad: check(observer.get_node("AI").context.coordination_assignment().get("role") == &"inspect_follow", "Strong-squad third member belongs to the same search queue")
		var receiver = assigned[0].get_node("AI")
		var old_assignment: Dictionary = receiver.context.coordination_assignment().duplicate(true)
		var reservations: Array = []
		for actor in assigned: reservations.append(actor.get_node("AI").context.coordination_assignment().reservation_id)
		var old_source: Dictionary = receiver.context.coordination_source(receiver.context.cooperation_target_id())
		var old_clue: Dictionary = receiver.context.cover_inspection_evidence()
		for index in assigned.size():
			assigned[index].global_position = arena.to_global(Vector3(-0.65 if index == 0 else 0.65, 0, 2.4))
			assigned[index].look_at(known)
		player.global_position = known
		var events: Array = []
		receiver.context.event_received.connect(func(event, data):
			if event == &"cooperation_intel": events.append(data.duplicate(true)))
		# Perception decides sight; both old and new reports have the same position.
		observer.global_position = arena.to_global(Vector3(2.3, 0, -1.8))
		observer.look_at(player.global_position)
		await physics_frame
		observer.get_node("AI")._physics_process(STEP)
		check(observer.get_node("AI").context.sees_player, "The third enemy really reacquires the crouched player beyond cover")
		for frame in 3: await _tick()
		check(not events.is_empty(), "Same-position reacquisition notifies already informed teammates")
		check(assigned.all(func(actor): return actor.get_node("AI").actions[&"search"]._inspection_assignment.is_empty()), "Both old endpoint executions cancel promptly")
		check(reservations.all(func(id): return not arena.cooperation._reservations.has(id)), "Both old endpoint reservations are released")
		var source: Dictionary = receiver.context.coordination_source(receiver.context.cooperation_target_id())
		check(not source.is_empty() and source.evidence_id != old_source.evidence_id, "Reacquisition gives planning a new identity at the same position")
		var stable_id: int = source.get("evidence_id", 0)
		var stable_events := events.size()
		var no_inspection := true
		var truthful := true
		var shots := 0
		for actor in assigned: shots += actor.shot_count
		for frame in 40:
			for index in assigned.size():
				assigned[index].global_position = arena.to_global(Vector3(-0.65 if index == 0 else 0.65, 0, 2.4))
			await _tick()
			for actor in assigned:
				var ai = actor.get_node("AI")
				no_inspection = no_inspection and ai.context.coordination_assignment().get("role") not in [&"inspect_left", &"inspect_right", &"search_sector"]
				truthful = truthful and not ai.context.sees_player and ai.context.utility_unseen_seconds > 0.0
		check(no_inspection, "Live teammate sight cannot rebuild the obsolete synchronized investigation")
		check(truthful, "Blind teammates retain truthful personal sight and sight age")
		var final_shots := 0
		for actor in assigned: final_shots += actor.shot_count
		check(final_shots == shots, "Receiving new contact does not authorize blind direct fire through cover")
		check(receiver.context.coordination_source(receiver.context.cooperation_target_id()).get("evidence_id") == stable_id and events.size() == stable_events, "Continuous same-position reports do not repeatedly restart decisions")
		observer.global_position = arena.to_global(Vector3(0, 0, 3.5))
		observer.look_at(player.global_position)
		for frame in 4: await _tick()
		var next_clue: Dictionary = receiver.context.cover_inspection_evidence()
		check(not observer.get_node("AI").context.sees_player and not next_clue.is_empty() and next_clue.id != old_clue.id and next_clue.checked_ends.is_empty(), "Losing contact again creates fresh investigation evidence without old checked ends")
		check(receiver.context.coordination_assignment().get("plan_id", 0) != old_assignment.get("plan_id"), "Old synchronized plan never resumes after another visual loss")
		var previous_events := events.size()
		observer.global_position = arena.to_global(Vector3(2.3, 0, -1.8))
		observer.look_at(player.global_position)
		for frame in 4: await _tick()
		check(events.size() > previous_events and receiver.context.coordination_source(receiver.context.cooperation_target_id()).get("evidence_id") != stable_id, "Another real reacquisition at the already notified position emits a fresh contact and plan identity")
	scene.queue_free()
	await physics_frame
