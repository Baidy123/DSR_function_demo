extends "res://tests/enemy/enemy_search_formation_test.gd"

## Real bodies execute the ordinary Utility loop. Displacement is injected
## once to model occupied destinations; no readiness or completion is forged.
func _run() -> void:
	await _formation_case(2, false, false, false, 2)
	await _formation_case(3, false, false, false, 2)
	await _formation_case(3, false, false, false, 3)
	await _formation_case(2, false, false, true)
	await _formation_case(3, false, false, true)
	await _formation_case(3, false, true, true)
	await _module_handoff_case()
	await _formation_case(3, false, false, false, 0, true)
	await _independent_passage_case()
	await _following_passage_case()
	print("SEARCH TRAFFIC: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _independent_passage_case() -> void:
	await _setup(false)
	var squad = Fixture.attach_squad(arena, actors, 2)
	for actor in actors: actor.get_node("AI").refresh_configuration(true)
	for frame in 12: await physics_frame
	var slots := {}
	for index in 2:
		var actor = actors[index]
		actor.global_position = arena.to_global(Vector3(-3.0 if index == 0 else 3.0, 0, 4.0))
		var entry: Vector3 = actor.global_position + Vector3(0, 0, -2)
		slots[actor.get_instance_id()] = {"entry": entry, "peek": entry + Vector3(0, 0, -1), "spacing": 1.2,
			"approach": PackedVector3Array([actor.global_position, entry]), "crossing": PackedVector3Array([entry, entry + Vector3(0, 0, -1)]),
			"passage_priority": index, "crossing_priority": index}
	var order := {"slots": slots}
	squad.coordinator._update_inspection_traffic(order, true)
	order.traffic.priority_moves.append(actors[0].get_instance_id())
	var context = actors[1].get_node("AI").context
	var own: Dictionary = slots[actors[1].get_instance_id()]
	var passage: Dictionary = squad.coordinator._inspection_passage(context, order, own, own.entry, STEP)
	check(passage.distance > 1.9 and passage.waiting_for.is_empty(), "Repairing one entrance does not stop a physically separate assigned corridor")
	scene.queue_free()
	await physics_frame

func _following_passage_case() -> void:
	await _setup(false)
	var squad = Fixture.attach_squad(arena, actors, 2)
	for actor in actors: actor.get_node("AI").refresh_configuration(true)
	for frame in 12: await physics_frame
	var slots := {}
	for index in 2:
		var actor = actors[index]
		actor.global_position = arena.to_global(Vector3(0, 0, 1.0 if index == 0 else 4.0))
		var entry: Vector3 = arena.to_global(Vector3(0, 0, -5.0 if index == 0 else -3.0))
		slots[actor.get_instance_id()] = {"entry": entry, "peek": entry + Vector3(0, 0, -1), "spacing": 1.2,
			"approach": PackedVector3Array([actor.global_position, entry]), "crossing": PackedVector3Array([entry, entry + Vector3(0, 0, -1)]),
			"passage_priority": index, "crossing_priority": index}
	var order := {"slots": slots}
	squad.coordinator._update_inspection_traffic(order, true)
	order.traffic.priority_moves.append(actors[0].get_instance_id())
	var context = actors[1].get_node("AI").context
	var own: Dictionary = slots[actors[1].get_instance_id()]
	var passage: Dictionary = squad.coordinator._inspection_passage(context, order, own, own.entry, STEP)
	check(passage.distance > 1.8 and passage.distance < 1.9, "A follower advances up to real clearance without waiting for the leader's whole journey")
	actors[0].global_position += Vector3(0, 0, -2)
	var advanced: Dictionary = squad.coordinator._inspection_passage(context, order, own, own.entry, STEP)
	check(advanced.distance > passage.distance + 1.9 and advanced.distance < 3.9, "Measured leader movement releases the traversed corridor while preserving body clearance")
	scene.queue_free()
	await physics_frame
