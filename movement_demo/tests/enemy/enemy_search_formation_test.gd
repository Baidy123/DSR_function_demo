extends "res://tests/enemy/enemy_cover_inspection_test.gd"

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")

func _run() -> void:
	if OS.get_cmdline_user_args().has("--modules"):
		await _module_handoff_case()
		print("SEARCH MODULE HANDOFF: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--blocked"):
		await _formation_case(2, false, false, false, 2)
		await _formation_case(3, false, false, false, 2)
		await _formation_case(3, false, false, false, 3)
		print("BLOCKED SEARCH FORMATION: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--crowded"):
		await _formation_case(2, false, false, true)
		await _formation_case(3, false, false, true)
		await _formation_case(3, false, true, true)
		print("CROWDED SEARCH FORMATION: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
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

func _formation_case(count: int, narrow: bool = false, encounter: bool = false, crowded: bool = false, displace: int = 0, reload_member: bool = false) -> void:
	print("FORMATION CASE count=", count, " narrow=", narrow, " encounter=", encounter, " crowded=", crowded)
	seed(20261021)
	await _setup(false)
	if displace > 0:
		arena.get_node("NavigationRegion3D").add_child(_box(Vector3(-2.1, 1.5, 0), Vector3(0.2, 3, 8), false))
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
	if reload_member:
		actors[0].weapon.reload_seconds = 2.0
		actors[0].ammo.magazine_rounds = 0
		# Inject the physical interruption under test through the real body API.
		# This case tests handoff DURING reload, not Utility's reload selection.
		actors[0].request_reload()
		actors[0].get_node("AI").invalidate_utility()
		for acceptance_frame in 12:
			await _tick()
			if actors[0].ammo.is_reloading: break
		check(actors[0].ammo.is_reloading, "Search handoff begins during an actual empty-magazine reload")
	# Establish evidence before crowding: a rear member can otherwise be
	# visually occluded by a teammate before the scenario even starts.
	if crowded:
		actors[0].global_position = arena.to_global(Vector3(-0.45, 0, 2.4))
		actors[1].global_position = arena.to_global(Vector3(-1.2, 0, 2.1))
		if count > 2: actors[2].global_position = arena.to_global(Vector3(-1.9, 0, 2.7))
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
	var assigned_positions := true
	var collisions := 0
	var stalled_frames := 0
	var longest_stall := 0
	var trace: Array = []
	var displaced := false
	var repair_seen := false
	var yield_seen := false
	var wait_seen := false
	var original_expiry := INF
	var physically_released := false
	var busy_reported := false
	var busy_kept := true
	for actor in actors: initial[actor.get_instance_id()] = actor.global_position
	for frame in 900:
		var before: Array = actors.map(func(actor): return actor.global_position)
		await _tick()
		if reload_member and actors[0].ammo.is_reloading:
			var busy_ai = actors[0].get_node("AI")
			busy_reported = busy_reported or busy_ai.context.coordination_motion_state().get("available_in", 0.0) > 0.0
			busy_kept = busy_kept and busy_ai.utility_current.get("id") == &"reload"
			premature = premature or actors.any(func(actor): return actor.get_node("AI").actions[&"search"]._inspection_phase == 3)
		if displace > 0 and not displaced and actors.all(func(actor): return actor.get_node("AI").context.coordination_assignment().get("accepted", false) and actor.get_node("AI").context.inspection_order().has("entry")):
			var positions: Array = actors.map(func(actor): return actor.get_node("AI").context.inspection_order().entry)
			for index in displace:
				actors[index].global_position = positions[(index + 1) % displace]
				actors[index].velocity = Vector3.ZERO
			original_expiry = actors[0].get_node("AI").context.coordination_assignment().expires_at
			displaced = true
		if not physically_released and actors.any(func(actor): return actor.get_node("AI").actions[&"search"]._inspection_phase == 3):
			physically_released = true
			premature = premature or not actors.all(func(actor):
				var order: Dictionary = actor.get_node("AI").context.inspection_order()
				return order.has("entry") and actor.global_position.distance_to(order.entry) <= 0.18)
		var assembling := false
		var advancing := false
		for actor in actors:
			var ai = actor.get_node("AI")
			var assignment: Dictionary = ai.context.coordination_assignment()
			var search = ai.actions[&"search"]
			var id: int = actor.get_instance_id()
			var order: Dictionary = ai.context.inspection_order()
			if displace > 0 and displaced and order.has("entry"):
				var traffic: Dictionary = squad.coordinator._inspection_orders.get(squad.coordinator._coordination_team(ai.context), {}).get("traffic", {})
				repair_seen = repair_seen or int(traffic.get("repairs", 0)) > 0
				yield_seen = yield_seen or not traffic.get("goals", {}).is_empty()
				wait_seen = wait_seen or not search._inspection_passage.get("waiting_for", []).is_empty()
				if not assignment.is_empty() and assignment.expires_at > original_expiry + 0.001: one_plan = false
			if order.has("entry"):
				assembling = assembling or (search._inspection_phase < 2 and ai.context._horizontal_distance(order.entry) > 0.05)
				assigned_positions = assigned_positions and order.has("approach") and order.has("passage_priority") and order.has("crossing_priority")
				for other in actors:
					var other_order: Dictionary = other.get_node("AI").context.inspection_order()
					if other == actor or not other_order.has("entry"): continue
					assigned_positions = assigned_positions and ai.context._horizontal_distance_between(order.entry, other_order.entry) >= 1.2
			advancing = advancing or actor.global_position.distance_to(before[actors.find(actor)]) > 0.01
			for collision in actor.get_slide_collision_count():
				if actor.get_slide_collision(collision).get_collider() in actors: collisions += 1
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
		stalled_frames = stalled_frames + 1 if assembling and not advancing else 0
		longest_stall = maxi(longest_stall, stalled_frames)
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
	if displace > 0:
		check(accepted.size() == count and accepted.values().count(&"inspect_right") == 1 and accepted.values().count(&"inspect_follow") == count - 1, "%d members keep all concrete slots in the single open column" % count)
	else:
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
	check(assigned_positions, "%d members each receive a distinct concrete position and complete ingress order" % count)
	check(collisions == 0 and longest_stall < 90, "%d members assemble without body collisions or a party-wide approach deadlock" % count)
	if displace > 0:
		check(displaced and repair_seen and yield_seen and wait_seen, "%d-way occupied-goal cycle is detected and a concrete yield is executed" % displace)
	if narrow: check(columns_only, "Both narrow cover ends use single-file ranks instead of blocked lateral offsets")
	if reload_member:
		check(busy_reported and busy_kept and not actors[0].ammo.is_reloading, "Real reload availability is reported and finishes before team movement takes over")
	print("FORMATION TRACE ", count, " accepted=", accepted, " observed=", observed, " ranks=", ranks, " min=", minimum, " ", JSON.stringify(trace))
	scene.queue_free()
	await physics_frame

func _module_handoff_case() -> void:
	await _setup(false)
	var squad = Fixture.attach_squad(arena, actors, 2)
	for actor in actors:
		actor.get_node("AI").refresh_configuration(true)
		actor.get_node("AI").set_physics_process(false)
	for frame in 12: await physics_frame
	for frame in 4: await _tick()
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 90:
		await _tick()
		if actors.all(func(actor): return actor.get_node("AI").context.coordination_assignment().get("accepted", false)): break
	var ai = actors[0].get_node("AI")
	var order: Dictionary = ai.context.inspection_order()
	var assignment: Dictionary = ai.context.coordination_assignment()
	check(not order.is_empty() and assignment.get("accepted", false), "Module handoff starts from a real accepted search task")
	var before: Dictionary = squad.coordinator._inspection_orders.duplicate(true)
	for query in 4: ai.context.inspection_status()
	check(before == squad.coordinator._inspection_orders, "Reading backend diagnostics cannot advance traffic or renew a task")
	if not assignment.is_empty():
		var stale := assignment.duplicate(true)
		stale.merge({"state": &"moving", "segment_boundary": false, "execution_valid": true, "motion_revision": -1}, true)
		check(not squad.coordinator.report_assignment(ai.context, stale), "An old motion revision cannot update the current search task")
	var definition = ai.unit_type.profile.definition(&"search")
	ai.unit_type.profile.default_behaviors.erase(definition)
	ai.refresh_configuration(true)
	check(not ai.actions.has(&"search") and ai.context.inspection_order().is_empty() and ai.context.coordination_assignment().is_empty(), "Removing Search immediately revokes its personal module and team task")
	for frame in 45: await _tick()
	check(actors.all(func(actor): return actor.get_node("AI").context.inspection_order().is_empty()), "A member without Search cannot leave the remaining member behind an impossible assembly barrier")
	check(ai.current_action == null or ai.current_action.action_id != &"search", "The coordinator does not secretly implement a removed personal action")
	ai.unit_type.profile.default_behaviors.append(definition)
	ai.refresh_configuration(true)
	check(ai.actions.has(&"search"), "Restoring Search reinstalls it through the unchanged module library")
	if not order.is_empty():
		ai.context.report_inspection_preparation(order, false)
		check(ai.context.inspection_order() != order, "A removed task's preparation report cannot revive its old order")
	scene.queue_free()
	await physics_frame
