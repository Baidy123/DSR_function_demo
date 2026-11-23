extends SceneTree

## Saved Lvl5, real wave spawn and the captured crowded contact positions.
## Positions/equipment are fixture inputs; orders, sight and progress are real.
var checks := 0
var failures := 0
var scene

class TestClock extends RefCounted:
	var elapsed := 0.0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--history-only"):
		_history()
		print("CONTACT RECOVERY HISTORY: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	seed(1)
	scene = load("res://scenes/world/levels/lvl_5.tscn").instantiate()
	scene.get_node("LevelFlow").free()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	if not await _wave(1): return
	for actor in scene.enemies.duplicate(): actor.receive_hit(100000.0)
	if not await _wave(2): return
	var squad = scene.get_node("SceneDirector/Wave2/Squad")
	var actors: Array = squad.get_children().filter(func(node): return node.has_node("AI"))
	check(actors.size() >= 6, "Saved second wave supplies the captured six-member squad")
	if actors.size() < 6:
		_finish()
		return
	var positions := [Vector3(11.383, 0, -2.834), Vector3(11.252, 0, -8.641), Vector3(10.223, 0, -4.934), Vector3(12.436, 0, -7.602), Vector3(11.111, 0, -11.847)]
	player.global_position = Vector3(8.75, 0, -12.024)
	for index in 5: actors[index].global_position = positions[index]
	for actor in actors.slice(5): actor.receive_hit(100000.0)
	actors.resize(5)
	var passage_case := OS.get_cmdline_user_args().has("--passage")
	if passage_case:
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(0.9, 2.0, 0.9)
		wall.add_child(shape)
		scene.add_child(wall)
		wall.global_position = Vector3(11.6, 1.0, -6.6)
	var initial_yields: int = squad.coordinator.yield_count
	var origins: Array = actors.map(func(actor): return actor.global_position)
	var peak_guards := [0.0, 0.0, 0.0, 0.0, 0.0]
	var guard_age := peak_guards.duplicate()
	var maximum_move := peak_guards.duplicate()
	var contact_seen := false
	var owned := true
	var clearance := INF
	var costs: Array[int] = []
	var stable_fire := 0
	var recovery_seen := false
	var joint_recovery_seen := false
	var yielding_starts := {}
	var yielding_movement := 0.0
	var first_fire: Array = actors.map(func(actor): return actor.shot_count)
	for frame in 1440:
		await physics_frame
		var co = squad.coordinator
		joint_recovery_seen = joint_recovery_seen or co._last_replan == &"contact_joint_yield"
		var total: int = scene.cooperation.last_advance_usec
		contact_seen = contact_seen or co._objective.get("phase") == &"contact"
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			if task.has("yield_for") and not yielding_starts.has(index): yielding_starts[index] = actor.global_position
			if yielding_starts.has(index): yielding_movement = maxf(yielding_movement, actor.global_position.distance_to(yielding_starts[index]))
			owned = owned and ai.utility_decision_count == 0 and (frame < 30 or not task.is_empty())
			for cost in ai.frame_costs.values(): total += int(cost)
			maximum_move[index] = maxf(maximum_move[index], actor.global_position.distance_to(origins[index]))
			if co._objective.get("phase") == &"contact" and task.get("role") == &"guard" and not ai.context.sees_player:
				guard_age[index] += 1.0 / 60.0
				peak_guards[index] = maxf(peak_guards[index], guard_age[index])
			else: guard_age[index] = 0.0
			var debug: Dictionary = ai.context.coordination_debug_snapshot()
			recovery_seen = recovery_seen or debug.get("contact_recovery", {}).get("round", 0) > 0
			for other in actors.slice(index + 1): clearance = minf(clearance, Vector2(actor.global_position.x - other.global_position.x, actor.global_position.z - other.global_position.z).length())
		if actors[1].shot_count > first_fire[1] or actors[2].shot_count > first_fire[2]: stable_fire += 1
		if frame > 60: costs.append(total)
		if frame % 180 == 0:
			print("CONTACT RECOVERY TRACE ", frame, " ", actors.map(func(actor):
				var ctx = actor.get_node("AI").context
				var task: Dictionary = ctx.coordination_assignment()
				return {"name": actor.name, "position": actor.global_position, "role": task.get("role"), "shots": actor.shot_count, "recovery": ctx.coordination_debug_snapshot().get("contact_recovery", {})}))
	check(contact_seen and actors.any(func(actor): return actor.get_node("AI").context.sees_player), "Real personal sight maintains squad contact")
	check(maximum_move[0] > 1.0 and maximum_move[3] > 1.0, "Both formerly stranded members actually leave their holding positions")
	check(actors[0].shot_count > first_fire[0] and actors[3].shot_count > first_fire[3], "Recovered members reach usable firing positions and fire")
	check(peak_guards[0] < 10.0 and peak_guards[3] < 10.0, "No blind guard is renewed indefinitely through successful teammate plans")
	check(stable_fire > 60, "Useful teammate fire continues during recovery")
	check(owned, "Recovery keeps squad authority and installed executors")
	check(clearance >= 0.64, "Recovery preserves real body clearance")
	if passage_case:
		check(joint_recovery_seen and squad.coordinator.yield_count > initial_yields, "A blocked local alternative triggers the contact recovery transaction")
		check(yielding_movement > 0.5, "The yielding teammate physically clears its original post")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Whole-frame P99 <16ms and peak <50ms remain unchanged")
	print("CONTACT RECOVERY METRICS ", {"movement": maximum_move, "guard_seconds": peak_guards, "clearance": clearance, "recovery_seen": recovery_seen, "contact_joint_yield": joint_recovery_seen, "yielding_movement": yielding_movement, "p99": costs[int(costs.size() * 0.99)], "peak": costs[-1]})
	_history()
	_finish()

func _history() -> void:
	var Recovery = load("res://scripts/enemy/services/squad_contact_recovery.gd")
	var history = Recovery.new()
	var bodies := {1: {"position": Vector3.ZERO, "radius": 0.35, "spacing_margin": 0.45}, 2: {"position": Vector3(0, 0, 2), "radius": 0.35, "spacing_margin": 0.45}}
	var tasks := {1: {"role": &"guard", "position": Vector3.ZERO, "task_id": 1}, 2: {"role": &"engage", "position": Vector3(0, 0, 2)}}
	var objective := {"phase": &"contact", "target_id": 10, "objective_id": 20, "position": Vector3(0, 0, 8)}
	history.observe(tasks, bodies, objective, 0.0)
	tasks[1].task_id = 99
	objective.objective_id = 21
	history.observe(tasks, bodies, objective, 1.4)
	check(is_equal_approx(history.snapshot(1, 1.4).age, 1.4), "Renewed task/objective tokens do not erase actual contact stagnation")
	var offer := {"role": &"engage", "position": Vector3(0, 0, 5), "route": PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 5)]), "look_position": objective.position}
	var candidates := {1: [offer], 2: []}
	check(history.finished(tasks, {}, bodies, objective, 1, 1.4).is_empty() and history.round_for(1) == 0, "An unfinished member's candidate cursor cannot be advanced by a teammate's completed pass")
	check(history.finished(tasks, candidates, bodies, objective, 1, 0.5, true).is_empty() and history.round_for(1) == 0, "Another member's focused pass cannot turn a brief guard into a stall")
	check(history.finished(tasks, candidates, bodies, objective, 1, 1.4).is_empty() and history.round_for(1) == 1, "A successful teammate plan still advances the stalled member to local alternatives first")
	check(history.take_priority_pass() and not history.take_priority_pass(), "A new recovery page gets one focused pass without permanently freezing teammate tactics")
	check(not history.finished(tasks, candidates, bodies, objective, 1, 1.5, true).is_empty() and history.round_for(1) == 1 and is_equal_approx(history.snapshot(1, 1.5).retry_in, 1.4), "A failed local pass can request yielding immediately without advancing or renewing the page clock")
	var request: Dictionary = history.finished(tasks, candidates, bodies, objective, 1, 3.0)
	check(request.get("member") == 1 and request.failure.offer.route.size() == 2 and request.failure.blockers == [2], "Subsequent repair preserves the rejected approach and its actual blocker")
	var sites := [{"position": offer.position}]
	check(history.filter_sites(1, sites, bodies, objective.position, 1, 3.1).is_empty(), "The unchanged blocked post is temporarily avoided")
	bodies[2].position.x = 0.6
	check(history.filter_sites(1, sites, bodies, objective.position, 1, 3.1).size() == 1, "A moving blocker immediately releases the failed-post restriction")
	bodies[2].position.x = 0.0
	check(history.filter_sites(1, sites, bodies, objective.position, 2, 3.1).size() == 1 and history.filter_sites(1, sites, bodies, objective.position, 1, 7.1).size() == 1, "Map changes and finite expiry cannot leave a permanently excluded post")
	var before: Dictionary = history.snapshot(1, 3.1)
	before.reason = &"consumer_mutation"
	check(history.snapshot(1, 3.1).reason != &"consumer_mutation", "Debug history is a read-only copy")
	bodies[1].position.x = 0.3
	history.observe(tasks, bodies, objective, 3.2)
	check(is_zero_approx(history.snapshot(1, 3.2).age), "Real body progress ends the previous stall")
	bodies[1].reloading = true
	history.observe(tasks, bodies, objective, 4.0)
	check(history.snapshot(1, 4.0).is_empty(), "Actual reload is not classified as idle guard starvation")
	bodies[1].reloading = false
	bodies[1].merge({"firearms": true, "visible": true, "fire_lane_valid": true, "can_attack": true, "rounds": 4})
	history.observe(tasks, bodies, objective, 4.5)
	check(history.snapshot(1, 4.5).is_empty(), "A legitimate stationary firing opportunity is preserved")
	bodies[1].visible = false
	history.observe(tasks, bodies, objective, 5.0)
	objective.phase = &"search"
	history.observe(tasks, bodies, objective, 6.0)
	check(history.members.is_empty(), "Search and synchronized inspections stay outside contact recovery")
	objective.phase = &"contact"
	history.observe(tasks, bodies, objective, 7.0)
	bodies.erase(1)
	tasks.erase(1)
	history.observe(tasks, bodies, objective, 8.0)
	check(history.members.is_empty(), "A departed member releases its recovery history")
	_yield_lifecycle()

func _yield_lifecycle() -> void:
	# Pure transaction lifecycle, separate from the real body tests above.
	var coordinator = load("res://scripts/enemy/services/squad_coordination.gd").new()
	var board := TestClock.new()
	coordinator.bind_environment(board)
	coordinator._objective = {"phase": &"contact", "objective_id": 1}
	coordinator._last_map_revision = 1
	coordinator._tasks = {
		1: {"role": &"move", "state": &"executing", "contact_yield": true, "yield_for": 2, "resume_position": Vector3.ZERO, "expires_at": 16.0, "objective_id": 1, "map_revision": 1},
		2: {"role": &"engage", "state": &"executing", "route": PackedVector3Array([Vector3.ZERO, Vector3(0,0,4)]), "expires_at": 16.0, "objective_id": 1, "map_revision": 1}}
	for id in [1,2]: coordinator._bodies[id] = {"position": Vector3.ZERO, "radius": 0.35, "spacing_margin": 0.45, "reloading": false, "can_reload": true, "rounds": 3}
	check(coordinator._continue_contact_yield(), "A valid joint departure survives ordinary reconsideration before bodies move")
	coordinator._tasks[3] = coordinator._tasks[2].duplicate(true)
	coordinator._tasks[3].state = &"blocked"
	coordinator._bodies[3] = coordinator._bodies[2].duplicate(true)
	check(not coordinator._continue_contact_yield() and coordinator._contact_yield_members() == [1,2], "An unrelated blocked teammate can replan without replacing the valid yielding pair")
	coordinator._tasks.erase(3)
	coordinator._bodies.erase(3)
	coordinator._tasks[2].state = &"blocked"
	var interrupted: bool = not coordinator._continue_contact_yield()
	coordinator._tasks[2].state = &"executing"
	coordinator._bodies[1].reloading = true
	interrupted = interrupted and not coordinator._continue_contact_yield()
	coordinator._bodies[1].reloading = false
	coordinator._last_map_revision = 2
	interrupted = interrupted and not coordinator._continue_contact_yield()
	coordinator._last_map_revision = 1
	board.elapsed = 16.1
	check(interrupted and not coordinator._continue_contact_yield(), "Blocking, actual reload, map changes and the original expiry release joint departure protection")
	board.elapsed = 1.0
	var requester: Dictionary = coordinator._tasks[2]
	coordinator._tasks.erase(2)
	check(not coordinator._continue_contact_yield(), "A departed requester cannot keep its teammate locked in a yield")
	coordinator._tasks[2] = requester
	coordinator._tasks[1].state = &"complete"
	coordinator._bodies[2].position = Vector3(0,0,4)
	coordinator._tasks[2].route = PackedVector3Array([Vector3(0,0,4)])
	check(not coordinator._continue_contact_yield(), "Actual passage clearance hands the completed yield back to normal planning")

func _wave(number: int) -> bool:
	for frame in 600:
		var state: Dictionary = scene.get_node("SceneDirector").debug_snapshot()
		if state.wave == number and state.state == "ACTIVE": return true
		await physics_frame
	check(false, "Requested wave becomes active")
	_finish()
	return false

func _finish() -> void:
	scene.get_node("SceneDirector").reset_encounter()
	scene.free()
	current_scene = null
	print("SQUAD CONTACT RECOVERY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
