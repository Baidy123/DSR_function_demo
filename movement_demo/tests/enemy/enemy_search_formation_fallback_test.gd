extends "res://tests/enemy/enemy_search_formation_test.gd"

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--saved-left-detour":
			for duration in [600, 1200]: await _saved_left_diagonal_case(0.0, duration)
			print("SAVED LEFT DETOUR: %d/%d passed" % [checks - failures, checks])
			quit(1 if failures else 0)
			return
		if argument == "--saved-left-repeat":
			for cycle in 3:
				await _saved_left_diagonal_case(0.0, 20, cycle > 0, true)
				player.global_position = arena.to_global(Vector3(0, 0, 40))
				for frame in 30: await physics_frame
				check(arena.players_inside.is_empty(), "Repeated arena: actual area exit is received")
				check(actors.all(func(actor): return actor.get_node("AI").context.inspection_order().is_empty() and actor.get_node("AI").context.coordination_assignment().is_empty()), "Repeated arena: leaving clears all old orders and assignments")
			scene.queue_free()
			await physics_frame
			print("SAVED LEFT REENTRY: %d/%d passed" % [checks - failures, checks])
			quit(1 if failures else 0)
			return
		if argument == "--saved-left-contact":
			await _saved_left_diagonal_case(0.0, 180)
			print("SAVED LEFT CONTACT: %d/%d passed" % [checks - failures, checks])
			quit(1 if failures else 0)
			return
		if argument == "--ingress-geometry":
			_ingress_geometry_case()
			quit(1 if failures else 0)
			return
		if argument == "--motion-corner":
			await _motion_corner_case()
			quit(1 if failures else 0)
			return
		if argument == "--saved-left-diagonal":
			await _saved_left_diagonal_case(0.7)
			await _saved_left_diagonal_case(0.0)
			print("SAVED LEFT DIAGONAL: %d/%d passed" % [checks - failures, checks])
			quit(1 if failures else 0)
			return
		if argument == "--saved-left-approach":
			await _saved_left_cover_case(true)
			quit(1 if failures else 0)
			return
		if argument == "--saved-left-cover":
			await _saved_left_cover_case()
			quit(1 if failures else 0)
			return
		if argument == "--opposite-entry":
			await _opposite_entry_case()
			quit(1 if failures else 0)
			return
		if argument == "--saved-arena":
			await _saved_arena_case()
			quit(1 if failures else 0)
			return
		if argument.begins_with("--kind="):
			await _fallback_case(StringName(argument.trim_prefix("--kind=")))
			quit(1 if failures else 0)
			return
	await _fallback_case(&"closed_end")
	await _fallback_case(&"blocked_leader")
	await _fallback_case(&"no_layout")
	await _fallback_case(&"high_cover")
	await _fallback_case(&"high_cover_full")
	await _fallback_case(&"open_loss")
	await _opposite_entry_case()
	await _motion_corner_case()
	_ingress_geometry_case()
	print("SEARCH FORMATION FALLBACK: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _ingress_geometry_case() -> void:
	var helper: Variant = load("res://scripts/enemy/services/enemy_search_formation.gd")
	var start := Vector3(-3, 0, 0)
	var finish := Vector3(3, 0, 0)
	check(is_equal_approx(helper.corridor_entry(start, finish, Vector3(0, 0, -3), Vector3(0, 0, 3), 1.0), 2.0), "Ingress corridor: crossing traffic waits a body clearance before the intersection")
	check(is_equal_approx(helper.corridor_entry(start, finish, Vector3.ZERO, Vector3.ZERO, 1.0), 2.0), "Ingress corridor: a parked member retains its footprint")
	check(is_equal_approx(helper.corridor_entry(start, finish, Vector3(-3, 0, 2), Vector3(3, 0, 2), 1.0), 6.0), "Ingress corridor: separated parallel lanes advance independently")
	var close := Vector3(0.8, 0, 0)
	check(is_equal_approx(helper.corridor_entry(Vector3.ZERO, Vector3(-2, 0, 0), close, close, 1.0, true), 2.0), "Ingress corridor: a close body can move out of actual occupied space")
	check(is_zero_approx(helper.corridor_entry(Vector3.ZERO, Vector3(-2, 0, 0), close, close, 1.0)), "Ingress corridor: physical recovery cannot bypass another member's reserved passage")
	var path := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 3), Vector3(3, 0, 3)])
	var remaining: PackedVector3Array = helper.remaining_path(Vector3(0, 0, 1), path)
	check(remaining.size() == 3 and remaining[1] == Vector3(0, 0, 3), "Ingress corridor: execution keeps the frozen corner instead of cutting directly to the slot")

## Geometry-only boundaries use an independent wall, including rotated walls.
## Actual perception, assignment and movement are covered by the saved route.
func _motion_corner_case() -> void:
	await _setup(false)
	for frame in 4: await _tick()
	var context = actors[0].get_node("AI").context
	for angle in [0.0, 0.65, PI * 0.5]:
		cover.rotation.y = angle
		await physics_frame
		var direction: Vector3 = cover.global_basis * Vector3(0.75, 0, -0.66).normalized()
		var evidence := {"position": cover.to_global(Vector3(0.5, -0.6, 2.3)), "direction": direction,
			"velocity": direction * 3.0, "observer_position": cover.to_global(Vector3(0, -0.6, 10))}
		var original := evidence.duplicate(true)
		var result: Dictionary = Geometry.nearby_investigation_cover(context, evidence)
		check(result.get("cover_id") == cover.get_instance_id(), "Motion corner: diagonal trail reaches the wall end, including rotated walls")
		check(evidence == original, "Motion corner: inference does not rewrite the observed source")
		player.global_position = arena.to_global(Vector3(-6, 0, -6))
		var after: Dictionary = Geometry.nearby_investigation_cover(context, evidence)
		check(not result.is_empty() and after.get("cover_id") == result.cover_id and after.get("inference_position") == result.inference_position, "Motion corner: hidden player position cannot change the hypothesis")
		evidence.velocity = -direction * 3.0
		evidence.direction = -direction
		check(Geometry.nearby_investigation_cover(context, evidence).is_empty(), "Motion corner: motion away from the wall does not infer a corner")
		evidence.position = cover.to_global(Vector3(0, -0.6, 2))
		evidence.direction = cover.global_basis * Vector3.FORWARD
		evidence.velocity = evidence.direction * 0.4
		check(Geometry.nearby_investigation_cover(context, evidence).is_empty(), "Motion corner: a short approach to the front middle remains a point clue")
	cover.rotation.y = 0.0
	scene.queue_free()
	await physics_frame

## Reproduces three members checking a point in front of CoverA, then two
## returning to personal cover while one searches alone. Runs the real physics
## AI loop with the saved map, complete training and original enemy spawns.
func _saved_left_diagonal_case(start_z: float, contact_frames: int = 20, reuse_scene: bool = false, keep_scene: bool = false) -> void:
	seed(20261021)
	if not reuse_scene:
		scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, start_z))
	actors = Fixture.members(arena)
	_use_strong_saved_squad()
	check(actors.size() == 3, "Saved diagonal: three original squad members")
	if actors.size() != 3:
		scene.queue_free()
		await physics_frame
		return
	for actor in actors: actor.look_at(player.global_position)
	var detailed: bool = contact_frames >= 600
	var history: Array = []
	for frame in contact_frames:
		await physics_frame
		if detailed and frame % 30 == 0: history.append(_saved_motion_sample(&"combat", frame))
	var witnesses: int = actors.filter(func(a): return a.get_node("AI").context.sees_player).size()
	if contact_frames == 20: check(witnesses == 1, "Saved diagonal: only one member initially sees the player")
	else: check(witnesses > 0, "Saved contact: normal AI engages the player before the retreat behind cover")
	for point in [Vector3(-2.2, 0, -1.9), Vector3(-4.84, 0, -1.9), Vector3(-4.84, 0, -0.2)]:
		while player.global_position.distance_to(arena.to_global(point)) > 0.01:
			player.global_position = player.global_position.move_toward(arena.to_global(point), 0.08)
			await physics_frame
			if detailed: history.append(_saved_motion_sample(&"retreat", history.size()))
	check(actors.all(func(a): return not a.get_node("AI").context.sees_player), "Saved diagonal: real movement behind CoverA breaks squad sight")
	var accepted := {}
	var first_plan := 0
	var same_plan := true
	var released := false
	var ready := false
	var contact := -1
	var kept_objective := true
	var no_early_completion := true
	var frozen_goal := {}
	var stable_goal := true
	var inferred_from_unbound := false
	var retained_actual_point := false
	var minimum := INF
	var planned_positions := true
	var evasions := 0
	var collisions := 0
	for frame in 600:
		await physics_frame
		if detailed and frame % 10 == 0: history.append(_saved_motion_sample(&"hidden", frame))
		var visible: bool = actors.any(func(a): return a.get_node("AI").context.sees_player)
		if visible and contact < 0: contact = frame
		if not released and actors.any(func(a): return a.get_node("AI").context.coordination_assignment().get("tactic") == &"inspect" and a.get_node("AI").context.coordination_assignment().get("phase") == &"executing"):
			released = true
			ready = actors.all(func(a):
				var ai = a.get_node("AI")
				var route: Dictionary = ai.actions[&"search"]._inspection_route
				return ai.context.coordination_assignment().get("accepted", false) and not route.is_empty() and a.global_position.distance_to(route.entry) <= 0.3)
		if contact < 0:
			for actor in actors:
				var ai = actor.get_node("AI")
				var order: Dictionary = ai.context.inspection_order()
				var assignment: Dictionary = ai.context.coordination_assignment()
				var route: Dictionary = ai.actions[&"search"]._inspection_route
				planned_positions = planned_positions and order.has("entry") and order.has("peek") and order.has("approach")
				if not route.is_empty() and order.has("entry"):
					planned_positions = planned_positions and route.entry == order.entry and route.peek == order.peek
				if actor.local_motion._point.is_finite(): evasions += 1
				for i in actor.get_slide_collision_count():
					if actor.get_slide_collision(i).get_collider() in actors: collisions += 1
				kept_objective = kept_objective and order.get("kind") == &"cover"
				no_early_completion = no_early_completion and not ai.actions[&"search"]._inspection_complete
				if not order.is_empty():
					if frozen_goal.is_empty(): frozen_goal = order.clue.duplicate(true)
					stable_goal = stable_goal and order.clue == frozen_goal
					var observed: Dictionary = ai.context.cover_inspection_evidence()
					retained_actual_point = retained_actual_point or (not observed.is_empty() and order.clue.position == observed.position)
					inferred_from_unbound = inferred_from_unbound or (observed.get("cover") == null and order.clue.has("inference_position") and order.clue.position == observed.position)
				if assignment.get("accepted", false) and assignment.tactic == &"inspect":
					if first_plan == 0: first_plan = assignment.plan_id
					same_plan = same_plan and first_plan == assignment.plan_id
					accepted[actor.get_instance_id()] = assignment.role
				elif accepted.size() == 3:
					same_plan = false
			for i in actors.size():
				for j in range(i + 1, actors.size()): minimum = minf(minimum, actors[i].global_position.distance_to(actors[j].global_position))
		if contact >= 0 and frame >= contact + 3: break
	# The short diagonal fixtures deliberately lose sight before a wall can be
	# associated. Long combat can legitimately yield direct cover evidence;
	# both must preserve that real last-seen point and one frozen objective.
	check(stable_goal and retained_actual_point and (contact_frames >= 600 or inferred_from_unbound), "Saved diagonal: one frozen corner hypothesis retains the actual last-seen point")
	check(kept_objective and no_early_completion, "Saved diagonal: observing the wall front cannot finish the unsearched cover objective")
	check(accepted.size() == 3 and same_plan, "Saved diagonal: all three keep the same task until real contact, without personal withdrawal")
	check(released and ready, "Saved diagonal: actual all-member assembly precedes release")
	check(contact >= 0 and contact < 480, "Saved diagonal: real corner contact within eight seconds after hiding")
	check(minimum >= 0.69, "Saved diagonal: distinct slots retain physical body clearance")
	check(planned_positions, "Saved diagonal: coordinator freezes each concrete slot and ingress route before dispatch")
	check(collisions == 0 and evasions == 0 and minimum >= 1.15, "Saved diagonal: whole ingress keeps queue clearance without body collisions or local scattering")
	check(actors.all(func(a): return a.get_node("AI").context.inspection_order().is_empty()), "Saved diagonal: new real contact cancels the old queue for everyone")
	print("SAVED DIAGONAL start_z=", start_z, " contact_frames=", contact_frames, " contact=", contact, " roles=", accepted, " min=", minimum, " collisions=", collisions, " evasions=", evasions)
	if detailed: print("SAVED MOTION HISTORY ", JSON.stringify(history))
	if not keep_scene:
		scene.queue_free()
		await physics_frame

func _use_strong_saved_squad() -> void:
	# The user's saved cooperation setting is editable. These explicit queue
	# cases require strong cooperation, on an instance-only resource copy.
	var squad = arena.get_node("Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = 2
	for actor in actors: actor.get_node("AI").refresh_configuration(true)

func _saved_motion_sample(stage: StringName, frame: int) -> Dictionary:
	return {"stage": stage, "frame": frame, "player": player.global_position, "members": actors.map(func(actor):
		var ai = actor.get_node("AI")
		return {"id": actor.get_instance_id(), "position": actor.global_position, "visible": ai.context.sees_player,
			"action": ai.utility_current.get("id"), "destination": ai.utility_current.get("destination", {}),
			"assignment": ai.context.coordination_assignment(), "inspection": ai.context.inspection_status()})}

func _opposite_entry_case() -> void:
	await _setup(false)
	for frame in 4: await _tick()
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	var context = actors[0].get_node("AI").context
	var geometry: Dictionary = Geometry.describe(context, context.cover_inspection_evidence())
	check(not geometry.is_empty(), "Opposite entry: real cover loss supplies frozen geometry")
	if not geometry.is_empty():
		actors[0].global_position = arena.to_global(Vector3(-2.3, 0, -1.1))
		var approach: PackedVector3Array = context.cover_selection._query_path_to(actors[0].global_position, geometry.ends[1].entry)
		check(not approach.is_empty(), "Opposite entry: actual navigation offers a route around the hidden side")
		var helper = preload("res://scripts/enemy/services/enemy_search_formation.gd")
		check(helper.route(context, geometry, {"side": 1, "row": 0, "depth": 1, "spacing": 1.2}).is_empty(), "Opposite entry: queue rejects crossing the hidden side to reach the other end")
		check(not helper.route(context, geometry, {"side": -1, "row": 0, "depth": 1, "spacing": 1.2}).is_empty(), "Opposite entry: the nearby legal end remains available")
	scene.queue_free()
	await physics_frame

## Optional diagnostic for the user's 2026-10-21 saved CoverA geometry and
## complete training. Kept separate because the scene is actively being edited.
func _saved_left_cover_case(from_spawn: bool = false) -> void:
	seed(20261021)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, -1.9) if from_spawn else Vector3(-2.0, 0, -1.6))
	actors = Fixture.members(arena)
	_use_strong_saved_squad()
	var starts := [Vector3(0, 0, 0.5), Vector3(1.2, 0, 2), Vector3(1.2, 0, -0.5)]
	check(actors.size() == starts.size(), "Saved left cover: the saved squad has three members")
	if actors.size() != starts.size():
		scene.queue_free()
		await physics_frame
		return
	for i in actors.size():
		if not from_spawn: actors[i].global_position = arena.to_global(starts[i])
		actors[i].get_node("AI").set_physics_process(false)
		actors[i].look_at(player.global_position)
	for frame in 15: await physics_frame
	var seen_directly := {}
	for frame in 4:
		await _tick()
		for actor in actors:
			if actor.get_node("AI").context.sees_player: seen_directly[actor.get_instance_id()] = true
	check(actors.any(func(a): return a.get_node("AI").context.sees_player), "Saved left cover: real sight establishes the shared contact")
	for point in [Vector3(-4.84, 0, -1.9 if from_spawn else -1.6), Vector3(-4.84, 0, 0.68)]:
		while player.global_position.distance_to(arena.to_global(point)) > 0.01:
			player.global_position = player.global_position.move_toward(arena.to_global(point), 0.08)
			await _tick()
			for actor in actors:
				if actor.get_node("AI").context.sees_player: seen_directly[actor.get_instance_id()] = true
	check(actors.all(func(a): return not a.get_node("AI").context.sees_player), "Saved left cover: walking behind CoverA breaks the whole squad's sight")
	if from_spawn: check(seen_directly.size() == 1, "Saved left approach: only one member ever saw the player before the shared search")
	var released := false
	var ready := false
	var premature := false
	var accepted := {}
	var first_plan := 0
	var same_plan := true
	var contact := -1
	var frozen_goal := {}
	var stable_goal := true
	var inferred_from_unbound := false
	for frame in 600:
		await _tick()
		if from_spawn and frame % 60 == 0:
			print("LEFT APPROACH ", frame, " ", actors.map(func(a):
				var ai = a.get_node("AI")
				var order: Dictionary = ai.context.inspection_order()
				var search = ai.actions[&"search"]
				return {"actor": a.name, "position": a.global_position, "action": ai.utility_current.get("id"), "plan": ai.utility_current.get("plan"), "kind": order.get("kind"), "side": order.get("side"), "row": order.get("row"), "phase": search._inspection_phase, "entry": search._inspection_route.get("entry"), "peek": search._inspection_route.get("peek")}))
		if not released and actors.any(func(a): return a.get_node("AI").context.coordination_assignment().get("tactic") == &"inspect" and a.get_node("AI").context.coordination_assignment().get("phase") == &"executing"):
			released = true
			ready = actors.all(func(a):
				var ai = a.get_node("AI")
				var route: Dictionary = ai.actions[&"search"]._inspection_route
				return ai.context.coordination_assignment().get("accepted", false) and not route.is_empty() and a.global_position.distance_to(route.entry) <= 0.3)
		for actor in actors:
			var ai = actor.get_node("AI")
			var order: Dictionary = ai.context.inspection_order()
			if from_spawn and not order.is_empty():
				var clue: Dictionary = order.clue
				if frozen_goal.is_empty(): frozen_goal = clue.duplicate(true)
				stable_goal = stable_goal and clue == frozen_goal
				var observed: Dictionary = ai.context.cover_inspection_evidence()
				inferred_from_unbound = inferred_from_unbound or (observed.get("cover") == null and clue.has("inference_position") and clue.position == observed.position)
			var assignment: Dictionary = ai.context.coordination_assignment()
			if assignment.get("accepted", false) and assignment.tactic == &"inspect":
				if first_plan == 0: first_plan = assignment.plan_id
				same_plan = same_plan and first_plan == assignment.plan_id
				accepted[actor.get_instance_id()] = assignment.role
			if ai.context.sees_player:
				premature = premature or not released
				if contact < 0: contact = frame
		if contact >= 0 and frame >= contact + 3: break
	check(accepted.size() == 3 and same_plan, "Saved left cover: all three accept the same search plan despite existing personal transfers")
	check(released and ready and not premature, "Saved left cover: nobody rushes into contact before all three actually assemble")
	check(contact >= 0 and contact < 480, "Saved left cover: the released queue really rounds the wall and reacquires within eight seconds")
	check(actors.all(func(a): return a.get_node("AI").context.inspection_order().is_empty()), "Saved left cover: renewed contact releases every queue restriction")
	if from_spawn: check(inferred_from_unbound and stable_goal, "Saved left approach: one frozen squad cover hypothesis preserves the actual last-seen point")
	print("SAVED LEFT COVER accepted=", accepted, " ready=", ready, " premature=", premature, " contact=", contact)
	scene.queue_free()
	await physics_frame

func _fallback_case(kind: StringName) -> void:
	seed(20261021)
	var high_cover: bool = kind in [&"high_cover", &"high_cover_full"]
	await _setup(kind == &"high_cover_full")
	var navigation = arena.get_node("NavigationRegion3D")
	if kind == &"open_loss":
		cover.collision_layer = 0
		cover.remove_from_group("cover_region")
		var mesh := NavigationMesh.new()
		mesh.vertices = PackedVector3Array([Vector3(-8, 0.3, -8), Vector3(8, 0.3, -8), Vector3(8, 0.3, 8), Vector3(-8, 0.3, 8)])
		mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		navigation.navigation_mesh = mesh
	elif high_cover:
		cover.get_node("CollisionShape3D").shape = cover.get_node("CollisionShape3D").shape.duplicate()
		cover.get_node("CollisionShape3D").shape.size.y = 2.2
		cover.position.y = 1.1
		player.global_position = arena.to_global(Vector3(3.3, 0, -0.8))
	elif kind == &"closed_end":
		navigation.add_child(_box(Vector3(-2.1, 1.5, 0), Vector3(0.2, 3, 8), false))
	else:
		navigation.add_child(_box(Vector3(-2.1, 1.5, -2.3), Vector3(0.8, 3, 0.8), false))
		if kind == &"no_layout":
			navigation.add_child(_box(Vector3(2.1, 1.5, -2.3), Vector3(0.8, 3, 0.8), false))
	var third = load("res://scenes/enemy/enemy.tscn").instantiate()
	third.weapon = WeaponData.new()
	third.position = Vector3(-1.3, 0, 3.6)
	arena.add_child(third)
	third.get_node("UnitType").profile = actors[0].get_node("UnitType").profile.duplicate(true)
	third.get_node("AI").training.profile = actors[0].get_node("AI").training.profile.duplicate(true)
	actors.append(third)
	var squad = Fixture.attach_squad(arena, actors, 2)
	for actor in actors:
		if kind == &"open_loss": actor.get_node("AI").training.profile.set_setting(&"perception", &"sight_distance", 6.0)
		actor.get_node("AI").refresh_configuration(true)
		actor.get_node("AI").set_physics_process(false)
		actor.look_at(player.global_position)
	for frame in 12: await physics_frame
	for frame in 4: await _tick()
	check(actors.all(func(a): return a.get_node("AI").context.sees_player), "%s: real initial sight" % kind)
	if kind == &"open_loss":
		player.global_position = arena.to_global(Vector3(0, 0, -4.0))
	elif high_cover:
		for frame in 55:
			player.global_position.x -= 0.06
			await _tick()
	else:
		player.request_crouch(true)
		for frame in 30:
			await physics_frame
			player._update_posture(STEP)
	for frame in 3: await _tick()
	check(actors.all(func(a): return not a.get_node("AI").context.sees_player), "%s: real cover loss" % kind)
	if kind == &"open_loss":
		check(actors.all(func(a): return not a.get_node("AI").context.cover_inspection_evidence().is_empty() and a.get_node("AI").context.cover_inspection_evidence().get("cover") == null), "Range loss shares a real last-seen clue with no associated cover")
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var initial := actors.map(func(a): return a.global_position)
	var first_moves := [-1, -1, -1]
	var accepted := {}
	var completed := {}
	var first_plan := 0
	var same_plan := true
	var minimum := INF
	var safe := true
	var unsafe: Array = []
	var rejected_frame := -1
	var all_finished := false
	var premature := false
	var released := false
	var release_ready := true
	var trace: Array = []
	var deadlines := {}
	var fixed_deadline := true
	for frame in 900:
		await _tick()
		for order: Dictionary in squad.coordinator._inspection_orders.values():
			if deadlines.has(order.evidence_id): fixed_deadline = fixed_deadline and order.expires_at <= deadlines[order.evidence_id]
			else: deadlines[order.evidence_id] = order.expires_at
		if not released and actors.any(func(a): return a.get_node("AI").context.coordination_assignment().get("tactic") == &"inspect" and a.get_node("AI").context.coordination_assignment().get("phase") == &"executing"):
			released = true
			release_ready = actors.all(func(a):
				var ai = a.get_node("AI")
				var route: Dictionary = ai.actions[&"search"]._inspection_route
				return ai.context.coordination_assignment().get("accepted", false) and not route.is_empty() and a.global_position.distance_to(route.entry) <= 0.3)
		for i in actors.size():
			var actor = actors[i]
			var ai = actor.get_node("AI")
			var search = ai.actions[&"search"]
			if first_moves[i] < 0 and actor.global_position.distance_to(initial[i]) > 0.4: first_moves[i] = frame
			var assignment: Dictionary = ai.context.coordination_assignment()
			if not released and not ai.context.inspection_order().is_empty() and not ai.context.sees_player:
				var geometry: Dictionary = search._inspection_geometry
				if not geometry.is_empty() and geometry.get("kind") != &"point":
					var box: CollisionShape3D = geometry.cover.get_ref().get_node("CollisionShape3D")
					var point: Vector3 = box.to_local(actor.global_position)
					var across: float = point.z if geometry.along_x else point.x
					if across * geometry.front_sign < -geometry.half_across and assignment.get("phase") != &"executing": premature = true
			if assignment.get("accepted", false) and assignment.get("role") in [&"inspect_left", &"inspect_right", &"inspect_follow"] and search._inspection_route.has("formation"):
				if first_plan == 0: first_plan = assignment.plan_id
				same_plan = same_plan and first_plan == assignment.plan_id
				accepted[i] = [assignment.role, search._inspection_route.formation.side, search._inspection_route.formation.row, search._inspection_route.stagger]
				if search._inspection_complete: completed[i] = true
			if not ai.context.sees_player and not ai.context.fire.request.is_empty() and unsafe.size() < 5: unsafe.append({"frame":frame,"actor":i,"request":ai.context.fire.request.duplicate(true)})
			safe = safe and (ai.context.sees_player or ai.context.fire.request.is_empty())
			for j in range(i): minimum = minf(minimum, actor.global_position.distance_to(actors[j].global_position))
		if kind == &"no_layout" and rejected_frame < 0 and squad.coordinator._inspection_orders.values().any(func(order): return order.slots.is_empty()): rejected_frame = frame
		if frame % 90 == 0: trace.append({"frame": frame, "positions": actors.map(func(a): return arena.to_local(a.global_position)), "plans": actors.map(func(a): return a.get_node("AI").utility_current.get("plan")), "phases": actors.map(func(a): return a.get_node("AI").actions[&"search"]._inspection_phase), "plan_ids": actors.map(func(a): return a.get_node("AI").context.coordination_assignment().get("plan_id", 0))})
		if completed.size() == actors.size() and squad.coordinator._coordination_plans.is_empty():
			all_finished = true
			break
		if kind == &"no_layout" and frame >= 420: break
	check(fixed_deadline, "%s: layout fallback never extends the original investigation deadline" % kind)
	if kind == &"no_layout":
		check(rejected_frame >= 0 and rejected_frame < 180, "Impossible layouts release the whole-party filter within three seconds")
		check(actors.all(func(a): return a.get_node("AI").context.inspection_order().is_empty()), "Rejected evidence does not restart an impossible assembly every decision")
		check(actors.any(func(a): return not a.get_node("AI").utility_current.is_empty()), "No-layout recovery leaves executable personal decisions instead of all standing by")
	else:
		if kind == &"open_loss":
			check(accepted.size() == 3 and accepted.values().filter(func(slot): return slot[0] == &"inspect_follow").size() == 2, "A clue with no wall still assigns all three members to one compact search")
		elif high_cover:
			check(accepted.size() == 3 and accepted.values().filter(func(slot): return slot[0] == &"inspect_left").size() == 1 and accepted.values().filter(func(slot): return slot[0] == &"inspect_right").size() == 1 and accepted.values().filter(func(slot): return slot[0] == &"inspect_follow").size() == 1, "Disappearing behind a high wall also commits the whole squad to two queues")
		else:
			check(accepted.size() == 3 and accepted.values().all(func(slot): return slot[1] == 1 and is_zero_approx(slot[3])), "%s: all three use the open end in one straight column" % kind)
			check(accepted.values().filter(func(slot): return slot[0] == &"inspect_right").size() == 1 and accepted.values().filter(func(slot): return slot[0] == &"inspect_follow").size() == 2, "%s: one leader and two rear slots" % kind)
		check(first_moves.all(func(frame): return frame >= 0 and frame < 180), "%s: every member starts advancing within three seconds" % kind)
		check(same_plan and all_finished, "%s: one accepted plan completes real observations for all members" % kind)
		check(not premature, "%s: nobody crosses behind the cover before the shared release" % kind)
		check(released and release_ready, "%s: shared release requires all three physically at their staging slots" % kind)
	check(minimum >= 0.69 and safe, "%s: physical separation and personal fire authority remain intact" % kind)
	if all_finished:
		for frame in 10: await _tick()
		check(actors.all(func(a): return a.get_node("AI").context.inspection_order().is_empty()), "%s: completed observations retire the shared objective without reassembling" % kind)
	print("FALLBACK TRACE ", kind, " first_moves=", first_moves, " accepted=", accepted, " completed=", completed, " rejected=", rejected_frame, " minimum=", minimum, " unsafe=", JSON.stringify(unsafe), " ", JSON.stringify(trace))
	scene.queue_free()
	await physics_frame

func _saved_arena_case() -> void:
	seed(20261021)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(6.9, 0, -0.8))
	actors = Fixture.members(arena)
	_use_strong_saved_squad()
	for actor in actors:
		actor.get_node("AI").set_physics_process(false)
		actor.look_at(player.global_position)
	for frame in 15: await physics_frame
	for frame in 4: await _tick()
	check(actors.all(func(a): return a.get_node("AI").context.sees_player), "Saved arena: squad sees standing player with its saved configuration")
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	check(actors.all(func(a): return not a.get_node("AI").context.sees_player), "Saved arena: crouching genuinely breaks every member's sight")
	var starts := actors.map(func(a): return a.global_position)
	var moved := {}
	var contact_frame := -1
	var accepted := {}
	for frame in 600:
		await _tick()
		for i in actors.size():
			var ai = actors[i].get_node("AI")
			if not moved.has(i) and actors[i].global_position.distance_to(starts[i]) > 0.4: moved[i] = frame
			var assignment: Dictionary = ai.context.coordination_assignment()
			if assignment.get("accepted", false) and assignment.tactic == &"inspect": accepted[i] = assignment.role
			if contact_frame < 0 and ai.context.sees_player: contact_frame = frame
		if contact_frame >= 0 and frame >= contact_frame + 3: break
	check(moved.size() == actors.size() and moved.values().all(func(frame): return frame < 180), "Saved arena: all members move within three seconds of hiding")
	check(accepted.size() == actors.size(), "Saved arena: the whole squad accepts a feasible queue")
	check(contact_frame >= 0 and contact_frame < 480, "Saved arena: actual movement reacquires the player within eight seconds")
	check(actors.all(func(a): return a.get_node("AI").context.inspection_order().is_empty()), "Saved arena: contact cancels every old assembly restriction")
	print("SAVED ARENA FALLBACK moved=", moved, " contact_frame=", contact_frame, " accepted=", accepted)
	scene.queue_free()
	await physics_frame
