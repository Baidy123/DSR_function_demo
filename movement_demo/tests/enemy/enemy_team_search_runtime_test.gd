extends "res://tests/enemy/enemy_team_basic_runtime_test.gd"

## Real perception/noise, normal Utility and actor physics select and execute all
## assignments. The fixture changes geometry/evidence, never action selection.
func _run() -> void:
	if OS.get_cmdline_user_args().has("--checkpoint-only"):
		await _passing_checkpoint_case()
		await _passing_checkpoint_case(true)
		print("TEAM SEARCH RUNTIME: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--yield-only"):
		await _yield_case()
		print("TEAM SEARCH RUNTIME: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--noise-only"):
		await _sector_case(true, false)
		print("TEAM SEARCH RUNTIME: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	await _sector_case(false, false)
	if not OS.get_cmdline_user_args().has("--first-only"):
		await _sector_case(true, false)
		await _sector_case(false, true)
	await _yield_case()
	await _passing_checkpoint_case()
	await _passing_checkpoint_case(true)
	print("TEAM SEARCH RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _passing_checkpoint_case(permanent: bool = false) -> void:
	var f: Dictionary = await _search_fixture(true)
	var blocker = load("res://scenes/enemy/enemy.tscn").instantiate()
	blocker.communication_group = &"sector_checkpoint_fixture"
	blocker.weapon = WeaponData.new()
	blocker.position = Vector3(7, 0, 7)
	f.arena.add_child(blocker)
	blocker.get_node("AI").set_physics_process(false)
	blocker.set_physics_process(false)
	var original: Dictionary = {}
	var mover
	var goal := Vector3.INF
	var elapsed := 0.0
	var cleared := false
	var occupied := false
	var completed := false
	var canceled := false
	var fixed := true
	var observed := false
	var stuck_window := 0.0
	for frame in 1500:
		await physics_frame
		if not original.is_empty() and not cleared:
			elapsed += STEP
			blocker.global_position = goal if permanent else goal + Vector3(0, 0, minf(0.5, elapsed * 0.24))
			occupied = occupied or not mover.get_node("AI").context.is_position_free(goal)
			if not permanent and elapsed >= 2.1:
				blocker.global_position = f.arena.to_global(Vector3(7, 0, 7))
				cleared = true
		for actor in f.actors:
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var task: Dictionary = ai.context.coordination_assignment()
			var search = ai.actions[&"search"]
			if original.is_empty() and task.get("accepted", false) and task.get("role") == &"search_sector" and task.phase == &"executing" and not search._sector_observing:
				original = task.duplicate(true)
				mover = actor
				goal = search._sector_destination()
				stuck_window = search.search_stuck_repath_seconds
				blocker.global_position = goal
			elif actor == mover:
				if task.get("assignment_id", 0) != original.assignment_id and not completed: canceled = true
				if task.get("assignment_id", 0) == original.assignment_id:
					fixed = fixed and task.expires_at == original.expires_at
					observed = observed or not search._sector_checked_tick.is_empty()
					completed = completed or (task.get("complete", false) and ai.context._coordination_execution_completed)
		if completed or canceled: break
	if permanent:
		check(occupied and canceled and not cleared and not completed and not observed, "A permanently occupied search checkpoint exits without reporting an observation or completion")
		check(fixed and elapsed >= stuck_window and elapsed <= stuck_window + 0.4, "A stationary ally retains the original search no-progress limit and fixed assignment deadline")
	else:
		check(occupied and cleared and elapsed >= 2.1, "A real slowly passing friendly capsule occupies an accepted search checkpoint beyond the ordinary stuck window")
		check(not canceled and fixed and completed and observed, "The same search assignment makes actual observations after the ally clears without replacing its identity or deadline")
	print("SECTOR_CHECKPOINT_SAMPLE ", JSON.stringify({"permanent": permanent, "occupied": occupied, "cleared": cleared, "completed": completed, "canceled": canceled, "seconds": elapsed}))
	await _dispose(f)

func _yield_case() -> void:
	var fixture: Dictionary = await _search_fixture(true)
	var original: Dictionary = {}
	var mover
	var origin := Vector3.INF
	var correction_seconds := 0.0
	var displaced := 0.0
	var canceled := false
	var fixed_deadline := true
	var completed := false
	var observations: Dictionary = {}
	var no_fire := true
	for frame in 1080:
		await physics_frame
		for actor in fixture.actors:
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var task: Dictionary = ai.context.coordination_assignment()
			var search = ai.actions[&"search"]
			if original.is_empty() and task.get("accepted", false) and task.get("role") == &"search_sector" and task.phase == &"executing" and not search._sector_observing:
				var partner = fixture.actors[1] if actor == fixture.actors[0] else fixture.actors[0]
				# Use the real finite capsule/path-validated body correction after
				# ordinary AI accepts a sector; never inject a plan or checked point.
				if actor.local_motion._start_side(partner, actor.global_position - partner.global_position, &"yield"):
					original = task.duplicate(true)
					mover = actor
					origin = actor.global_position
			elif actor == mover:
				if actor.local_motion.has_temporary_correction(): correction_seconds += STEP
				displaced = maxf(displaced, actor.global_position.distance_to(origin))
				if task.get("assignment_id", 0) != original.assignment_id and not completed: canceled = true
				if task.get("assignment_id", 0) == original.assignment_id:
					fixed_deadline = fixed_deadline and task.expires_at == original.expires_at
					no_fire = no_fire and ai.context.fire.request.is_empty()
					for point: Vector3 in search._sector_checked_tick:
						observations[point] = ai.context.perception.can_observe_position(point)
					completed = completed or (task.get("complete", false) and ai.context._coordination_execution_completed)
		if completed or canceled: break
	check(not original.is_empty() and correction_seconds > 0.9 and displaced > 0.5, "An assigned search performs real physical yielding beyond its ordinary stuck window")
	check(not canceled and fixed_deadline and completed, "The same search assignment completes after yielding within its original deadline")
	check(no_fire and not observations.is_empty() and observations.values().all(func(value): return value), "Yield recovery retains actual observed points and the nonfiring search contract")
	print("SECTOR_YIELD_SAMPLE ", JSON.stringify({"seconds": correction_seconds, "displaced": displaced, "canceled": canceled, "completed": completed, "observations": observations.size()}))
	await _dispose(fixture)

func _wall(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body

func _search_fixture(noise: bool) -> Dictionary:
	seed(20261011)
	var f: Dictionary = await _fixture(2, true)
	var region: NavigationRegion3D = f.arena.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var xs: Array[float] = [-8.0, -1.0, 1.0, 8.0]
	var zs: Array[float] = [-8.0, -1.0, 1.0, 8.0]
	for z in zs:
		for x in xs: vertices.append(Vector3(x, 0.3, z))
	mesh.vertices = vertices
	for z in 3:
		for x in 3:
			if x == 1 and z == 1: continue
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	region.navigation_mesh = mesh
	_wall(region, Vector3(0, 1.2, 0), Vector3(1.2, 2.4, 1.2))
	_wall(region, Vector3(-5.5, 1.5, 0), Vector3(0.2, 3, 18))
	for index in f.actors.size():
		var actor = f.actors[index]
		actor.global_position = f.arena.to_global(Vector3(4, 0, -1.4 if index == 0 else 1.4))
		actor.get_node("AI").training.profile.set_setting(&"search", &"search_radius", 6.0)
		actor.get_node("AI").training.profile.set_setting(&"perception", &"hearing_enabled", noise)
		actor.look_at(actor.global_position + Vector3.RIGHT if noise else f.player.global_position)
	for frame in 8: await physics_frame
	if noise:
		for actor in f.actors: actor.get_node("AI").perception.receive_noise(f.player, f.player.global_position, 20.0, 1.0)
		check(f.actors.all(func(actor): return actor.get_node("AI").context.noise_search_origin.is_finite() and not actor.get_node("AI").context.has_visual_memory), "Real hearing begins targetless investigation while actors look away from the source")
	else:
		for frame in 4:
			await physics_frame
			for actor in f.actors: actor.get_node("AI")._physics_process(STEP)
		check(f.actors.all(func(actor): return actor.get_node("AI").context.sees_player), "Both searchers acquire the initial target through real perception")
	f.known = f.player.global_position
	f.player.global_position = f.arena.to_global(Vector3(-7, 0, 0))
	for frame in 3: await physics_frame
	return f

func _sector_case(noise: bool, block: bool) -> void:
	var f: Dictionary = await _search_fixture(noise)
	var starts: Array[Vector3] = []
	for actor in f.actors: starts.append(actor.global_position)
	var moved: Array[float] = [0.0, 0.0]
	var assigned: Dictionary = {}
	var observations: Dictionary = {}
	var completed: Dictionary = {}
	var completed_actors: Dictionary = {}
	var observed_boundaries := true
	var different := false
	var identities := true
	var no_fire := true
	var personal_progress := false
	var blocked_id := 0
	var blocked_owner := -1
	var blocked_at := -1
	var blocked_complete := false
	var recovered := false
	var fixed: Dictionary = {}
	var deadlines_fixed := true
	var plan_history: Dictionary = {}
	var extension_stable := true
	var extensions := 0
	var trace_state: Dictionary = {}
	var trace: Array = []
	var first_assignments: Dictionary = {}
	var first_assignment_aborted := false
	# Discover work within the original 14 seconds, then observe each accepted
	# assignment until its original deadline. A valid 20-second search may still
	# be observing its second point when an unconditional 14-second loop ends.
	for frame in 2041:
		await physics_frame
		for index in f.actors.size():
			var ai = f.actors[index].get_node("AI")
			ai._physics_process(STEP)
			if block: continue
			var task: Dictionary = ai.context.coordination_assignment()
			var search = ai.actions[&"search"]
			if task.get("role") == &"search_sector" and task.get("accepted", false) and not first_assignments.has(index):
				first_assignments[index] = task.duplicate(true)
			if not first_assignments.has(index): continue
			if task.get("assignment_id", 0) != first_assignments[index].assignment_id:
				first_assignment_aborted = first_assignment_aborted or not completed_actors.has(index)
				continue
			for point: Vector3 in search._sector_checked_tick:
				observations[[task.assignment_id, point]] = {"actor": index, "visible": ai.context.perception.can_observe_position(point), "sector": search._sector_plan.template.sector_key}
				observed_boundaries = observed_boundaries and bool(search.execution_contract(false).segment_boundary)
			if ai.context._coordination_execution_completed:
				completed[task.assignment_id] = index
				completed_actors[index] = true
		var current_sectors: Array = []
		for shared: Dictionary in f.actors[0].get_node("AI").context.cooperation.coordination_debug_snapshot(&"_coordination_plans").values():
			if not shared.assignments.all(func(entry): return entry.role == &"search_sector"): continue
			var entries: Dictionary = {}
			for entry: Dictionary in shared.assignments: entries[entry.actor_id] = entry.assignment_id
			if plan_history.has(shared.plan_id):
				var previous: Dictionary = plan_history[shared.plan_id]
				if entries.size() > previous.entries.size():
					extensions += 1
					extension_stable = extension_stable and previous.expires_at == shared.expires_at and previous.phase == shared.phase
					for owner in previous.entries: extension_stable = extension_stable and entries.get(owner) == previous.entries[owner]
			plan_history[shared.plan_id] = {"entries": entries, "phase": shared.phase, "expires_at": shared.expires_at}
		for index in f.actors.size():
			var actor = f.actors[index]
			var ai = actor.get_node("AI")
			var context = ai.context
			var search = ai.actions[&"search"]
			moved[index] = maxf(moved[index], actor.global_position.distance_to(starts[index]))
			var task: Dictionary = context.coordination_assignment()
			if task.get("role") == &"search_sector":
				if not fixed.has(task.assignment_id): fixed[task.assignment_id] = task.expires_at
				deadlines_fixed = deadlines_fixed and fixed[task.assignment_id] == task.expires_at
				identities = identities and task.target_id == (0 if noise else f.player.get_instance_id())
				if task.get("accepted", false) and not search._sector_plan.is_empty():
					var sector: String = search._sector_plan.template.sector_key
					assigned[index] = sector
					current_sectors.append(sector)
					if block and context._coordination_execution_completed:
						completed[task.assignment_id] = index
						completed_actors[index] = true
						if task.assignment_id == blocked_id: blocked_complete = true
					if block and different and blocked_id == 0 and context._horizontal_distance(search._sector_destination()) > 1.0:
						blocked_id = task.assignment_id
						blocked_owner = index
						blocked_at = frame
						_wall(f.arena.get_node("NavigationRegion3D"), f.arena.to_local(search._sector_destination()) + Vector3.UP * 1.5, Vector3(1.6, 3, 1.6))
					if task.assignment_id == blocked_id and task.get("complete", false): blocked_complete = true
			else:
				personal_progress = personal_progress or (not ai.utility_current.is_empty() and actor.get_local_movement_velocity().length() > 0.1)
			if index == blocked_owner and frame > blocked_at + 15 and task.get("assignment_id", 0) != blocked_id and not ai.utility_current.is_empty(): recovered = true
			if not search._sector_assignment.is_empty(): no_fire = no_fire and context.fire.request.is_empty()
			if noise: identities = identities and not context.has_visual_memory and context.coordination_source(context.cooperation_target_id()).is_empty() and context.cooperation_checked_points().is_empty()
			var signature := str([task.get("assignment_id", 0), search._sector_index, search._sector_observing])
			if frame % 90 == 0 or trace_state.get(index) != signature:
				trace_state[index] = signature
				trace.append({"frame": frame, "actor": index, "action": ai.utility_current.get("id", &""), "plan": ai.utility_current.get("plan", &""), "role": task.get("role", &""), "phase": task.get("phase", &""), "assignment": task.get("assignment_id", 0), "deadline": task.get("expires_at", 0), "now": context.coordination_now(), "goal": search._sector_destination(), "observe": search._sector_observe_remaining, "position": actor.global_position, "offers": search._sector_offers.size(), "map": context.coordination_search_revision(), "source": search._sector_source(), "templates": search.evaluation_points().size(), "coverage_pending": search.coverage.has_pending_preparation(), "failures": context.squad_coordinator._coordination_failures.duplicate(true)})
		if current_sectors.size() == 2 and current_sectors[0] != current_sectors[1]: different = true
		if block and blocked_id > 0 and recovered and frame >= blocked_at + 120: break
		if block and frame >= 839: break
		if not block:
			if first_assignment_aborted: break
			if first_assignments.size() < 2 and frame >= 839: break
			if first_assignments.size() == 2:
				var deadline := maxf(first_assignments[0].expires_at, first_assignments[1].expires_at)
				if f.actors[0].get_node("AI").context.coordination_now() >= deadline: break
		if not block and completed_actors.size() >= 2 and observations.size() >= 4: break
	check(not assigned.is_empty() and different, "noise=%s block=%s: ordinary AI accepts distinct prepared sectors" % [noise, block])
	check(moved[0] > 0.5 and moved[1] > 0.5, "noise=%s block=%s: both actors really walk their legal investigation routes" % [noise, block])
	check(identities and deadlines_fixed and extension_stable and no_fire, "noise=%s block=%s: evidence domain, stable extension identities, fixed deadlines and nonfiring search remain valid" % [noise, block])
	if block:
		check(blocked_id > 0 and recovered and not blocked_complete, "An actual obstacle invalidates the accepted destination without false completion and the owner resumes a legal action")
	else:
		check(completed_actors.size() == 2 and observations.size() >= 4 and observations.values().all(func(value): return value.visible) and observed_boundaries, "noise=%s: both actors complete actual per-point observations with legal segment boundaries" % noise)
		check(first_assignments.size() == 2 and not first_assignment_aborted and completed_actors.size() == 2, "noise=%s: each first accepted assignment completes within its original lease without replacement" % noise)
		check(personal_progress, "noise=%s: personal investigation continues while shared templates and offers are preparing" % noise)
	print("TEAM SEARCH TRACE noise=", noise, " block=", block, " assigned=", assigned, " observations=", observations.size(), " completed=", completed, " moved=", moved, " blocked=", blocked_id, " recovered=", recovered, " extensions=", extensions, " ", JSON.stringify(trace))
	await _dispose(f)
