extends SceneTree

## Scheduling contracts plus a saved-map run. Runtime orders and perception
## come from the original area clock; only initial positions/player motion change.
const Coordinator = preload("res://scripts/enemy/services/squad_coordination.gd")
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
var checks := 0
var failures := 0
var scene

class ObservationBoard extends RefCounted:
	var elapsed := 0.0
	var contact := true
	var observation := {"position": Vector3.ZERO, "aim_position": Vector3.UP, "captured_at": 0.0, "target_id": 10}
	var serial := 100
	func planning_observation(_context) -> Dictionary: return observation.duplicate(true)
	func has_visual_contact(_context, _target: int) -> bool: return contact
	func allocate_coordination_id() -> int:
		serial += 1
		return serial
	func release_squad_reservations(_coordinator) -> void: pass

class MemberContext extends RefCounted:
	var spawn_search_hint := {}
	func cooperation_target_id() -> int: return 10

class CommitBoundary extends "res://scripts/enemy/services/squad_coordination.gd":
	var commit_attempts := 0
	var allow_commit := false
	func _commit(_proposals: Dictionary, _traffic: Dictionary) -> bool:
		commit_attempts += 1
		return allow_commit

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	_objective_contract()
	_holding_preparation_contract()
	_incumbent_contract()
	if not OS.get_cmdline_user_args().has("--contract-only"): await _runtime()
	print("SQUAD DISPATCH CONTINUITY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _objective_contract() -> void:
	var board := ObservationBoard.new()
	var context := MemberContext.new()
	var co = Coordinator.new()
	co.bind_environment(board)
	co._members = {1: {"context": weakref(context)}}
	co._bodies = {1: {"position": Vector3(5, 0, 0)}}
	co._profiles = {1: {"firearms": false, "actions": {&"engage": {"roles": [&"guard", &"engage"]}}}}
	co._objective = {"phase": &"contact", "objective_id": 1, "target_id": 10, "position": Vector3.ZERO}
	co._tasks = {1: Contract.task({"member_id": 1}, {"role": &"guard", "position": Vector3(5, 0, 0), "objective_id": 1}, 0.0)}
	co._preparation = {"members": [1], "works": {1: {"cursor": 7}}, "started_at": 0.0}
	var original: Dictionary = co._preparation.duplicate(true)
	for step in 5:
		board.observation.position = Vector3(float(step + 1) * 1.1, 0, 0)
		board.observation.captured_at += 0.2
		co._update_objective()
	check(co._preparation == original and co._objective.objective_id == 1, "Continuous same-target movement across metre boundaries preserves in-flight preparation")
	co._preparation.clear()
	co._update_objective()
	check(co._objective.position == board.observation.position, "The next preparation boundary samples the latest legal target position")
	board.observation.position.x += 0.6
	co._update_objective()
	check(co._objective.position == board.observation.position, "A melee guard also refreshes a sub-metre target change before preparing again")
	co._preparation = original.duplicate(true)
	board.observation.position.x += 0.1
	co._update_objective()
	check(co._preparation == original and co._objective.position != board.observation.position, "Guard target refresh never resets an unfinished action cursor")
	board.observation.target_id = 11
	co._update_objective()
	check(co._preparation.is_empty() and co._objective.target_id == 11, "A genuinely different target immediately supersedes old preparation")
	co._preparation = original.duplicate(true)
	board.contact = false
	co._update_objective()
	check(co._preparation.is_empty() and co._objective.phase == &"search", "Actual loss of contact still switches to search and rejects old contact work")
	co._preparation = original.duplicate(true)
	co.invalidate_member(1)
	check(co._preparation.is_empty(), "Environment invalidation still clears obsolete preparation")

func _holding_preparation_contract() -> void:
	var board := ObservationBoard.new()
	var co = Coordinator.new()
	co.bind_environment(board)
	co._objective = {"phase": &"contact", "objective_id": 1, "target_id": 10, "position": Vector3(0, 0, 8)}
	co._last_map_revision = 1
	for id in [1, 2]:
		var position := Vector3(float(id - 1) * 3.0, 0, 0)
		co._bodies[id] = {"position": position, "radius": 0.35, "spacing_margin": 0.45}
		co._profiles[id] = {"profile_id": str(id), "firearms": false, "actions": {&"engage": {"roles": [&"guard", &"engage"], "basis": "dispatch_contract"}}}
		co._tasks[id] = {"role": &"guard", "action": &"engage", "position": position, "route": PackedVector3Array([position]), "estimate": 40.0}
	co._template = Contract.template(co._profiles, 1)
	co._contact_recovery.observe(co._tasks, co._bodies, co._objective, 0.0)
	board.elapsed = 1.4
	co._preparation = {"members": [1, 2], "candidates": {1: [co._tasks[1]], 2: [co._tasks[2]]},
		"works": {1: {"done": true}, 2: {"done": false, "offer_cursor": {"next": 17}}}}
	var unfinished: Dictionary = co._preparation.works[2].duplicate(true)
	co._preparation.solution = co._planner.begin({"members": co._bodies, "profiles": co._profiles,
		"template": co._template, "objective": co._objective, "candidates": co._preparation.candidates})
	co._finish_plan(9223372036854775807)
	check(co._contact_recovery.round_for(1) == 1 and not co._preparation.works.has(1), "An all-guard partial result lets a completed member start recovery immediately")
	check(co._contact_recovery.round_for(2) == 0 and co._preparation.works[2] == unfinished, "The slow teammate keeps its unfinished cursor without false completion")
	check(not co._preparation.has("solution") and co._due == board.elapsed and co._tasks.values().all(func(task): return task.role == &"guard"), "Recovery resumes the original scheduler without inventing or partially committing tasks")

func _incumbent_contract() -> void:
	# Detached scheduling boundary: real pure planner, controllable transaction
	# rejection. The saved-map branch separately exercises the actual commit.
	var board := ObservationBoard.new()
	var co := CommitBoundary.new()
	co.bind_environment(board)
	co._objective = {"phase": &"contact", "objective_id": 1, "target_id": 10, "position": Vector3(0, 0, 8)}
	co._bodies = {1: {"position": Vector3.ZERO, "radius": 0.35, "spacing_margin": 0.45}}
	co._profiles = {1: {"profile_id": "1", "firearms": false, "actions": {&"engage": {"roles": [&"guard", &"engage"], "basis": "dispatch_contract"}}}}
	co._template = Contract.template(co._profiles, 1)
	var guard := {"role": &"guard", "state": &"executing", "action": &"engage", "position": Vector3.ZERO, "route": PackedVector3Array([Vector3.ZERO]), "estimate": 40.0}
	var engage := {"role": &"engage", "action": &"engage", "position": Vector3(0, 0, 2), "route": PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 2)]), "estimate": 1.0}
	co._tasks = {1: guard.duplicate(true)}
	co._preparation = {"members": [1], "candidates": {1: [guard, engage]}, "works": {1: {"done": true}}}
	var work: Dictionary = co._planner.begin({"members": co._bodies, "profiles": co._profiles, "template": co._template, "objective": co._objective, "candidates": co._preparation.candidates})
	co._planner._consider_seed(work, {1: work.snapshot.candidates[1][0]})
	co._preparation.solution = work
	var stack: Array = work.stack.duplicate(true)
	var trials: int = work.trials
	co._finish_plan(0)
	check(co.commit_attempts == 1 and co._tasks[1] == guard and work.stack == stack and work.trials == trials, "A rejected early complete table preserves tasks, combination cursor and consumed search budget")
	co._finish_plan(0)
	check(co.commit_attempts == 1 and co._preparation.has("solution"), "The same rejected incumbent is not revalidated every frame")
	co._objective.phase = &"search"
	work.erase("publish_attempt_cost")
	co._finish_plan(0)
	check(co.commit_attempts == 1 and co._preparation.has("solution"), "Search never publishes an unfinished combination result")
	co._objective.phase = &"contact"
	co.allow_commit = true
	co._finish_plan(9223372036854775807)
	check(co.commit_attempts == 2 and co._preparation.is_empty(), "The completed comparison still retries the original full-table transaction")

func _wave(number: int) -> bool:
	for frame in 600:
		var state: Dictionary = scene.get_node("EnemyWaves").debug_snapshot()
		if state.wave == number and state.state == "ACTIVE": return true
		await physics_frame
	check(false, "Requested saved wave becomes active")
	return false

func _runtime() -> void:
	seed(1)
	scene = load("res://scenes/world/levels/lvl_5.tscn").instantiate()
	scene.get_node("LevelFlow").free()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	if not await _wave(1): _cleanup(); return
	for frame in 180: await physics_frame
	for actor in scene.enemies.duplicate(): actor.receive_hit(100000.0)
	if not await _wave(2): _cleanup(); return
	var squad = scene.get_node("EnemyWaves/Wave2/Squad")
	var actors: Array = squad.get_children().filter(func(node): return node.has_node("AI"))
	check(actors.size() == 6, "The saved second wave supplies the actual six-member squad")
	if actors.size() != 6: _cleanup(); return
	var positions := [Vector3(11.383, 0, -2.834), Vector3(11.252, 0, -8.641), Vector3(10.223, 0, -4.934), Vector3(12.436, 0, -7.602), Vector3(12.2, 0, -11.847), Vector3(10.1, 0, -8.5)]
	for index in actors.size(): actors[index].global_position = positions[index]
	var player_shape = player.get_node("CollisionShape3D").shape
	check(preload("res://scripts/systems/character_geometry.gd").can_sweep(player, Vector3(8.75, 0, -12), Vector3(8.75, 0, -9), player_shape.height, player_shape.radius, true), "The entire moving-target trajectory is clear for the real player capsule")
	var longest_guard := 0
	var guard_frames := 0
	var inactive_frames := 0
	var longest_inactive := 0
	var owned := true
	var first_dispatch := -1
	var first_movement := -1
	var contact_frame := -1
	var movement := 0.0
	var previous_positions: Array = positions.duplicate()
	var shot_attempts: Array = actors.map(func(actor): return actor.shot_attempt_count)
	var costs: Array[int] = []
	for frame in 720:
		player.global_position = Vector3(8.75, 0, -10.5 + sin(float(frame) / 60.0 * 1.4) * 1.5)
		await physics_frame
		var co = squad.coordinator
		var all_guard := true
		var all_inactive := true
		var total: int = scene.cooperation.last_advance_usec
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			all_guard = all_guard and task.get("role") == &"guard"
			owned = owned and ai.utility_decision_count == 0 and not task.is_empty()
			movement = maxf(movement, actor.global_position.distance_to(positions[index]))
			if first_movement < 0 and actor.global_position.distance_to(positions[index]) > 0.15: first_movement = frame
			var active: bool = actor.global_position.distance_to(previous_positions[index]) > 0.001 or actor.melee_active or actor.ammo.is_reloading or actor.shot_attempt_count > shot_attempts[index]
			var normal_fire_pause: bool = ai.context.sees_player and ai.context.last_seen_aim_position.is_finite() and ai.context.fire.fire_pause_remaining > 0.0 and actor.ammo.magazine_rounds > 0
			all_inactive = all_inactive and not active and not normal_fire_pause
			previous_positions[index] = actor.global_position
			shot_attempts[index] = actor.shot_attempt_count
			for cost in ai.frame_costs.values(): total += int(cost)
		if co._objective.get("phase") == &"contact":
			if contact_frame < 0: contact_frame = frame
			if not all_guard and first_dispatch < 0: first_dispatch = frame
			guard_frames = guard_frames + 1 if all_guard else 0
			longest_guard = maxi(longest_guard, guard_frames)
			inactive_frames = inactive_frames + 1 if all_inactive else 0
			longest_inactive = maxi(longest_inactive, inactive_frames)
		else:
			guard_frames = 0
			inactive_frames = 0
		if frame > 60: costs.append(total)
		if OS.get_cmdline_user_args().has("--trace") and frame < 180:
			var solution: Dictionary = co._preparation.get("solution", {})
			print("DISPATCH TRACE ", {"frame": frame, "version": co._version, "map": co._last_map_revision, "objective": co._objective.get("objective_id"),
				"age": co.elapsed - co._preparation.get("started_at", co.elapsed), "stage": co.frame_costs.stage, "reason": co._last_replan,
				"works": co._preparation.get("works", {}).values().map(func(work): return [work.get("defense_ready"), work.get("done"), work.get("offer_cursor", {}).get("offers", []).size()]),
				"trials": solution.get("trials", 0), "best": solution.get("best", {}).values().map(func(task): return task.role)})
	check(contact_frame >= 0 and first_dispatch >= 0 and first_dispatch - contact_frame <= 90, "A continuously moving target receives a useful whole-team plan within 1.5 seconds of contact")
	check(longest_guard <= 90, "No repeated all-guard dispatch gap exceeds 1.5 seconds during the moving-target run")
	check(first_movement >= 0 and first_movement - contact_frame <= 90, "Actual bodies start moving within 1.5 seconds, not merely receiving a new role label")
	check(longest_inactive <= 90, "The whole squad never loses all physical activity for 1.5 seconds outside normal firing pauses")
	check(movement > 1.0 and actors.any(func(actor): return actor.melee_count > 0), "Commands produce real movement and melee strikes during continued target motion")
	check(owned, "Every member remains under squad command with no personal Utility fallback")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Existing whole-frame P99 <16ms / peak <50ms limits remain unchanged")
	print("DISPATCH METRICS ", {"first_dispatch_frames": first_dispatch - contact_frame, "first_movement_frames": first_movement - contact_frame, "all_guard_frames": longest_guard, "all_inactive_frames": longest_inactive,
		"movement": movement, "p99_usec": costs[int(costs.size() * 0.99)], "peak_usec": costs[-1]})
	_cleanup()

func _cleanup() -> void:
	scene.get_node("EnemyWaves").reset_encounter()
	scene.free()
	current_scene = null
