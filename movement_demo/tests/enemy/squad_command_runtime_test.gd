extends SceneTree

## Saved map, real perception and original AI/body/fire loops. No injected
## candidates, acceptance, readiness, observation, or shot facts.
var checks := 0
var failures := 0
var scene: Node
var arena: Node3D
var player: Node3D
var actors: Array = []
var level := 1
var mixed := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): level = int(arg.trim_prefix("--level="))
	seed(20261023)
	mixed = OS.get_cmdline_user_args().has("--mixed")
	scene = load("res://scenes/main.tscn").instantiate()
	var squad = scene.get_node("Arena/Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = level
	actors = scene.get_node("Arena").find_children("*", "CharacterBody3D", true, false).filter(func(actor): return actor.has_node("AI"))
	if mixed:
		actors[2].get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres")
		actors[2].get_node("Training").profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
		actors[2].weapon = load("res://resources/weapons/enemy_test_melee.tres")
		actors[1].get_node("Training").profile = actors[1].get_node("Training").profile.duplicate(true)
		actors[1].get_node("Training").profile.selected_tactics.clear()
	root.add_child(scene)
	current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get("combat").set_physics_process(false)
	player.get("health").debug_invincible = true
	player.global_position = arena.to_global(Vector3.ZERO)
	if OS.get_cmdline_user_args().has("--patrol"):
		player.global_position = arena.to_global(Vector3(-4.84, 0, 0.68))
		for actor in actors: actor.look_at(actor.global_position + Vector3.RIGHT)
		await _patrol_case()
		scene.queue_free()
		await physics_frame
		print("SQUAD PATROL RUNTIME: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	var starts: Array = actors.map(func(actor): return actor.global_position)
	for actor in actors: actor.look_at(player.global_position)
	var owned := true
	var accepted := {}
	var first_seen := {}
	var first_shot := {}
	var minimum := INF
	var frame_costs: Array[int] = []
	for frame in 600:
		await physics_frame
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			if frame > 5 and level > 0: owned = owned and not task.is_empty()
			if task.get("accepted", false): accepted[index] = true
			if ai.context.sees_player and not first_seen.has(index): first_seen[index] = frame
			if actor.shot_count + actor.melee_count > 0 and not first_shot.has(index): first_shot[index] = frame
			for other in actors.slice(index + 1): minimum = minf(minimum, actor.global_position.distance_to(other.global_position))
		var total := 0
		for actor in actors:
			for cost in actor.get_node("AI").frame_costs.values(): total += int(cost)
		frame_costs.append(total + arena.get("cooperation").last_advance_usec)
		if frame % 120 == 0: print("COMMAND TRACE ", frame, " ", JSON.stringify(actors.map(_trace)))
	check(actors.size() == 3, "Saved map supplies the current three members")
	check(owned, "Every active commanded member continuously owns a task")
	if level > 0:
		check(actors.all(func(actor): return actor.get_node("AI").utility_decision_count == 0), "Commanded AI never evaluates personal Utility")
		check(accepted.size() == actors.size(), "All members actually accept commands")
	else:
		check(actors.all(func(actor): return actor.get_node("AI").utility_decision_count > 0), "Intel-only members actually use personal Utility")
	check(first_seen.size() == actors.size(), "All members obtain personal sight during real contact")
	check(first_shot.size() == actors.size(), "All members actually attack through original fire or melee control")
	check(minimum >= 0.64, "Physical bodies keep their original collision clearance")
	frame_costs.sort()
	if level > 0:
		check(frame_costs[int(frame_costs.size() * 0.99)] < 16000 and frame_costs[-1] < 50000, "Original full-frame P99 <16ms / maximum <50ms budget")
	print("COMMAND RESULT level=", level, " seen=", first_seen, " shots=", first_shot,
		" moved=", actors.map(func(actor): return actor.global_position.distance_to(starts[actors.find(actor)])),
		" min=", minimum, " p99_usec=", frame_costs[int(frame_costs.size() * 0.99)])
	if OS.get_cmdline_user_args().has("--search") and level > 0: await _search_case()
	if level > 0: await _protocol_and_lifecycle()
	scene.queue_free()
	await physics_frame
	if level > 0: await _reload_scene()
	print("SQUAD COMMAND RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _search_case() -> void:
	var initial_waits: int = arena.get_node("Squad").coordinator.traffic_wait_count
	if OS.get_cmdline_user_args().has("--blocked-exit"):
		var blocker := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(4.8, 3.0, 1.8)
		collision.shape = shape
		blocker.add_child(collision)
		arena.add_child(blocker)
		blocker.global_position = arena.to_global(Vector3(-3.6, 1.5, 4.92))
	if OS.get_cmdline_user_args().has("--crowded"):
		# Relocate only the fixture's bodies into a narrow saved-wall approach.
		# Do not inject plans, acceptance, perception, or navigation results.
		for index in actors.size():
			actors[index].global_position = arena.to_global(Vector3(-0.8 + index * 1.2, 0, -2.0))
			actors[index].velocity = Vector3.ZERO
	for point in [Vector3(-4.84, 0, -1.9), Vector3(-4.84, 0, 0.68)]:
		while player.global_position.distance_to(arena.to_global(point)) > 0.01:
			player.global_position = player.global_position.move_toward(arena.to_global(point), 0.08)
			await physics_frame
	check(actors.all(func(actor): return not actor.get_node("AI").context.sees_player), "Saved left wall actually occludes all three members")
	var reacquired := -1
	var owned := true
	var search_members := {}
	var objective := 0
	var stable := true
	var starts: Array = actors.map(func(actor): return actor.global_position)
	var closest := INF
	var barriers_seen := {}
	var barrier_waits := 0
	var released := false
	var hidden_stable := true
	var false_completion_rejected := false
	var waits := {}
	for frame in 900:
		await physics_frame
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			owned = owned and not task.is_empty() and ai.utility_decision_count == 0
			if task.get("role") == &"search" and task.get("accepted", false): search_members[index] = true
			if task.get("state") == &"waiting" and task.get("reason") == &"occupied_corridor": waits[index] = true
			if not false_completion_rejected and task.get("role") == &"search" and actor.global_position.distance_to(task.position) > 0.5:
				false_completion_rejected = not ai.context.report_command(task, &"complete", {"observed": true})
			for other in actors.slice(index + 1): closest = minf(closest, actor.global_position.distance_to(other.global_position))
		var squad = arena.get_node("Squad").coordinator
		var current: Dictionary = squad._objective
		for key in squad._barriers:
			barriers_seen[key] = true
			released = released or squad._barriers[key].released
		for task in squad._tasks.values():
			if task.get("reason") == &"staging_barrier": barrier_waits += 1
		if current.get("phase") == &"search":
			if objective == 0: objective = current.objective_id
			else: stable = stable and objective == current.objective_id
		elif current.get("phase") == &"contact": objective = 0
		if frame == 20 and actors.all(func(actor): return not actor.get_node("AI").context.sees_player):
			var frozen: Vector3 = current.position
			player.global_position.z += 0.2
			await physics_frame
			if actors.all(func(actor): return not actor.get_node("AI").context.sees_player): hidden_stable = squad._objective.position == frozen
		if actors.any(func(actor): return actor.get_node("AI").context.sees_player) and reacquired < 0: reacquired = frame
		if frame % 120 == 0: print("SEARCH TRACE ", frame, " ", JSON.stringify(actors.map(_trace)))
		if frame == 80 and OS.get_cmdline_user_args().has("--capture-debug"):
			root.get_node("DebugSettings").enabled = true
			for redraw in 3: await process_frame
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			check(not picture.is_empty() and picture.save_png("res://logs/coordinator_rewrite_20261023/new_command_routes.png") == OK, "Rendered world-space command routes are captured")
	check(owned, "Loss, congestion and replanning never return tactical authority to personal Utility")
	check(search_members.size() == actors.size(), "All members actually execute search commands")
	check(stable, "The search objective survives layout changes until a real new contact")
	check(reacquired >= 0 and reacquired <= 480, "Saved wall search actually reacquires within the existing eight-second boundary")
	check(closest >= 0.64, "Search preserves physical body separation")
	if OS.get_cmdline_user_args().has("--blocked-exit"):
		check(reacquired >= 0 and stable and search_members.size() == actors.size(), "A physically blocked cover exit still yields a complete alternative search layout")
	check(hidden_stable and false_completion_rejected, "Hidden movement cannot update the clue; unobserved arrival cannot mark coverage")
	if OS.get_cmdline_user_args().has("--crowded"):
		check(arena.get_node("Squad").coordinator.traffic_wait_count > initial_waits and actors.all(func(actor): return actor.global_position.distance_to(starts[actors.find(actor)]) > 1.0), "Crowded wall approach identifies blockers and all members actually clear the passage")
	if level == 2 and not mixed:
		var squad = arena.get_node("Squad").coordinator
		check(squad.barrier_wait_count > 0 and squad.barrier_release_count > 0, "Strong coordination actually stages and releases participating observers, including the loss transition")
	print("SEARCH RESULT reacquired=", reacquired, " min=", closest, " barriers=", barriers_seen.size(), " waits=", barrier_waits, " released=", released, " moved=", actors.map(func(actor): return actor.global_position.distance_to(starts[actors.find(actor)])))

func _trace(actor) -> Dictionary:
	var ai = actor.get_node("AI")
	var debug: Dictionary = ai.context.coordination_debug_snapshot()
	var task: Dictionary = debug.get("task", {})
	return {"name": actor.name, "position": actor.global_position, "visible": ai.context.sees_player,
		"shots": actor.shot_count, "role": task.get("role"), "state": task.get("state"), "goal": task.get("position"), "reason": task.get("reason"), "planning": debug.get("planning_reason"),
		"replan": debug.get("last_replan"), "utility": ai.utility_decision_count}

func _protocol_and_lifecycle() -> void:
	var squad = arena.get_node("Squad").coordinator
	var template: Dictionary = squad._template.duplicate(true)
	var profiles: Dictionary = squad._profiles.duplicate(true)
	var ai = actors[0].get_node("AI")
	var task: Dictionary = ai.context.coordination_assignment()
	var stale := task.duplicate(true)
	stale.version = int(stale.version) - 1
	var coverage: Dictionary = squad._covered.duplicate(true)
	check(not ai.context.report_command(stale, &"complete", {"observed": true}) and squad._covered == coverage, "Stale feedback cannot complete a task or mark coverage")
	var before: Dictionary = squad._tasks.duplicate(true)
	for repeat in 30:
		var snapshot: Dictionary = ai.context.coordination_debug_snapshot()
		snapshot.get("task", {}).clear()
	check(before == squad._tasks, "Debug reads and caller edits cannot alter live tasks")
	var legal := true
	for actor in actors:
		var context = actor.get_node("AI").context
		var profile: Dictionary = context.member_capability_snapshot()
		var current: Dictionary = context.coordination_assignment()
		legal = legal and profile.actions.keys() == actor.get_node("AI").actions.keys() and profile.actions.has(current.action) and profile.actions[current.action].roles.has(current.role)
	check(legal, "Battle profiles and executed roles match the actual assembled action instances")
	var training = actors[0].get_node("Training")
	training.profile = training.profile.duplicate(true)
	training.profile.selected_tactics.clear()
	actors[0].ammo.magazine_rounds = 0
	var reloaded := false
	var occupied := false
	var owned := true
	for frame in 420:
		await physics_frame
		var current: Dictionary = ai.context.coordination_assignment()
		owned = owned and not current.is_empty() and ai.utility_decision_count == 0
		occupied = occupied or actors[0].ammo.is_reloading and current.get("role") == &"reload"
		if occupied and not actors[0].ammo.is_reloading and actors[0].ammo.magazine_rounds > 0: reloaded = true
	check(occupied and reloaded and owned, "Empty magazine triggers an actual reload and keeps commanded ownership")
	check(squad._profiles == profiles and squad._template == template, "Runtime training edits and reload do not rebuild this battle's profiles or template")
	for victim in [actors[2], actors[1]]:
		var id: int = victim.get_instance_id()
		victim.receive_hit(victim.health + 1.0)
		for frame in 120: await physics_frame
		var clean: bool = not squad.member_ids().has(id)
		for current in squad._tasks.values(): clean = clean and not current.waiting_for.has(id)
		check(clean, "Death removes the member's task, reservation and passage dependencies")
	var start: Vector3 = actors[0].global_position
	var shots: int = actors[0].shot_count
	for frame in 240: await physics_frame
	check(squad.member_ids().size() == 1 and ai.utility_decision_count == 0 and not ai.context.coordination_assignment().is_empty(), "One survivor remains under squad command")
	check(actors[0].shot_count > shots or actors[0].global_position.distance_to(start) > 0.5, "The survivor actually continues combat or movement")
	print("SURVIVOR RESULT ", JSON.stringify(_trace(actors[0])))

func _reload_scene() -> void:
	var fresh = load("res://scenes/main.tscn").instantiate()
	var new_members: Array = fresh.get_node("Arena").find_children("*", "CharacterBody3D", true, false).filter(func(actor): return actor.has_node("AI"))
	var training = new_members[0].get_node("Training")
	training.profile = training.profile.duplicate(true)
	training.profile.selected_tactics.clear()
	fresh.get_node("Arena/Squad").profile = load("res://resources/enemy/cooperation/tactical.tres").duplicate(true)
	root.add_child(fresh)
	current_scene = fresh
	var target = fresh.get_node("Player")
	target.set_physics_process(false)
	target.get("combat").set_physics_process(false)
	target.get("health").debug_invincible = true
	target.global_position = fresh.get_node("Arena").to_global(Vector3.ZERO)
	for frame in 30: await physics_frame
	var coordinator = fresh.get_node("Arena/Squad").coordinator
	var profile: Dictionary = new_members[0].get_node("AI").context.member_capability_snapshot()
	check(profile.ready and not profile.actions.has(&"suppression") and not profile.actions.has(&"cooperate") and coordinator._template.members.size() == 3, "Reloading the scene builds fresh profiles and template from the changed training")
	fresh.queue_free()
	await physics_frame

func _patrol_case() -> void:
	var last: Array = actors.map(func(actor): return actor.global_position)
	var early: Array[float] = [0.0, 0.0, 0.0]
	var later: Array[float] = [0.0, 0.0, 0.0]
	var completed_sites: Array[Dictionary] = [{}, {}, {}]
	var owned := true
	var peaceful := true
	var minimum := INF
	for frame in 1200:
		await physics_frame
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			if task.get("role") == &"patrol" and task.get("state") == &"complete":
				completed_sites[index][task.site_key] = true
			if frame > 5:
				owned = owned and not task.is_empty() and ai.utility_decision_count == 0
				peaceful = peaceful and not ai.context.sees_player and arena.get_node("Squad").coordinator._objective.get("phase") == &"patrol"
			var distance: float = actor.global_position.distance_to(last[index])
			if frame < 600: early[index] += distance
			else: later[index] += distance
			last[index] = actor.global_position
			for other in actors.slice(index + 1): minimum = minf(minimum, actor.global_position.distance_to(other.global_position))
		if frame % 240 == 0: print("PATROL TRACE ", frame, " ", JSON.stringify(actors.map(_trace)))
	check(peaceful, "Saved map remains genuinely unalerted throughout the patrol reproduction")
	check(owned, "Every patrol member remains under continuous squad command")
	check(early.all(func(distance): return distance > 1.0), "Every member reaches the first patrol leg")
	check(later.all(func(distance): return distance > 2.0), "After arrival every member continues to distinct patrol destinations")
	check(completed_sites.all(func(sites): return sites.size() >= 2), "Every member physically completes at least two distinct patrol posts")
	check(minimum >= 0.64, "Continuing patrol keeps real body separation")
	print("PATROL RESULT early=", early, " later=", later, " completed=", completed_sites.map(func(sites): return sites.size()), " minimum=", minimum)
