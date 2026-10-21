extends "res://tests/enemy/enemy_cover_inspection_test.gd"

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			await _formation_case(int(argument.trim_prefix("--count=")))
			print("SEARCH FORMATION: %d/%d passed" % [checks - failures, checks])
			quit(1 if failures else 0)
			return
	await _formation_case(3)
	await _formation_case(4)
	await _formation_case(6)
	await _formation_case(4, true)
	await _formation_case(3, false, true)
	print("SEARCH FORMATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _formation_case(count: int, narrow: bool = false, encounter: bool = false) -> void:
	print("FORMATION CASE count=", count, " narrow=", narrow, " encounter=", encounter)
	seed(20261021)
	await _setup(false)
	if narrow:
		for side in [-1, 1]:
			arena.get_node("NavigationRegion3D").add_child(_box(Vector3(side * 2.8, 1.5, 0), Vector3(0.2, 3, 8), false))
	while actors.size() < count:
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		actor.weapon = WeaponData.new()
		var row := floorf((actors.size() - 2) / 2.0)
		actor.position = Vector3((-1.0 if actors.size() % 2 == 0 else 1.0) * (1.3 + row * 1.5), 0, 3.6 + row * 1.3)
		arena.add_child(actor)
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
		actor.get_node("AI").training.profile = actors[0].get_node("AI").training.profile.duplicate(true)
		actor.get_node("AI").refresh_configuration(true)
		actors.append(actor)
	var squad = Fixture.attach_squad(arena, actors, 2)
	for actor in actors:
		actor.get_node("AI").refresh_configuration(true)
		actor.get_node("AI").set_physics_process(false)
		actor.look_at(player.global_position)
	for frame in 12: await physics_frame
	for frame in 4: await _tick()
	check(actors.all(func(actor): return actor.get_node("AI").context.sees_player), "%d-member squad establishes real sight" % count)
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	check(actors.all(func(actor): return not actor.get_node("AI").context.sees_player), "%d-member squad loses real sight at the same cover" % count)
	var known: Vector3 = player.global_position
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var accepted := {}
	var observed := {}
	var ranks := {}
	var movement := {}
	var initial := {}
	var old_plan := 0
	var one_plan := true
	var premature := false
	var minimum := INF
	var all_finished := false
	var columns_only := true
	var encounter_started := false
	var encounter_frame := -1
	var old_reservations: Array = []
	var safe_fire := true
	var trace: Array = []
	for actor in actors: initial[actor.get_instance_id()] = actor.global_position
	for frame in 900:
		await _tick()
		for actor in actors:
			var ai = actor.get_node("AI")
			var assignment: Dictionary = ai.context.coordination_assignment()
			var search = ai.actions[&"search"]
			var id: int = actor.get_instance_id()
			movement[id] = maxf(movement.get(id, 0.0), actor.global_position.distance_to(initial[id]))
			if assignment.get("accepted", false) and not search._inspection_route.is_empty():
				if old_plan == 0: old_plan = assignment.plan_id
				one_plan = one_plan and old_plan == assignment.plan_id
				accepted[id] = assignment.role
				var formation: Dictionary = search._inspection_route.get("formation", {})
				if narrow: columns_only = columns_only and is_zero_approx(float(search._inspection_route.stagger))
				ranks[id] = [formation.get("side"), formation.get("row")]
				if search._inspection_phase == search.InspectionPhase.CHECK and accepted.size() != count: premature = true
				if search._inspection_complete: observed[id] = true
			if not ai.context.sees_player and not ai.context.fire.request.is_empty(): safe_fire = false
		for i in count:
			for j in range(i + 1, count): minimum = minf(minimum, actors[i].global_position.distance_to(actors[j].global_position))
		if frame % 90 == 0:
			trace.append({"frame": frame, "positions": actors.map(func(actor): return actor.global_position), "phases": actors.map(func(actor): return actor.get_node("AI").actions[&"search"]._inspection_phase)})
		if encounter and accepted.size() == count:
			if not encounter_started and actors.any(func(actor): return actor.get_node("AI").actions[&"search"]._inspection_phase == 3):
				encounter_started = true
				player.global_position = known
				for actor in actors: old_reservations.append(actor.get_node("AI").context.coordination_assignment().reservation_id)
			if encounter_started and encounter_frame < 0 and actors.any(func(actor): return actor.get_node("AI").context.sees_player): encounter_frame = frame
			if encounter_frame >= 0 and frame >= encounter_frame + 3: break
		if observed.size() == count and squad.coordinator._coordination_plans.is_empty():
			all_finished = true
			break
	check(accepted.size() == count and accepted.values().count(&"inspect_left") == 1 and accepted.values().count(&"inspect_right") == 1 and accepted.values().count(&"inspect_follow") == count - 2, "%d members accept two leaders and a slot for every rear member" % count)
	check(ranks.values().size() == count and not premature, "%d members stage as one search party before crossing" % count)
	if encounter:
		check(encounter_frame >= 0, "A real queue leader rounds the cover and sees the player at the reported position")
		check(actors.all(func(actor): return actor.get_node("AI").context.coordination_assignment().get("plan_id", 0) != old_plan and actor.get_node("AI").actions[&"search"]._inspection_route.is_empty()), "Real contact cancels the entire old queue within three updates")
		check(old_reservations.all(func(id): return not arena.cooperation._reservations.has(id)), "Contact releases every old queue reservation")
		check(actors.all(func(actor): return actor.get_node("AI").context.inspection_order().is_empty()), "Live contact ends the whole-squad search objective")
	else:
		check(one_plan and all_finished, "%d members finish the same whole-squad search without cancel-and-retry" % count)
	check(movement.values().all(func(distance): return distance > 0.5) and minimum >= 0.69, "%d members physically advance with body clearance" % count)
	check(safe_fire, "Queue membership does not authorize blind fire")
	if narrow: check(columns_only, "Both narrow cover ends use single-file ranks instead of blocked lateral offsets")
	print("FORMATION TRACE ", count, " accepted=", accepted, " observed=", observed, " ranks=", ranks, " min=", minimum, " ", JSON.stringify(trace))
	scene.queue_free()
	await physics_frame
