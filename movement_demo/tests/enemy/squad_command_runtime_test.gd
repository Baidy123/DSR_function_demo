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
var _search_audit: Dictionary = {}
var _search_audit_previous: Dictionary = {}

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
	if OS.get_cmdline_user_args().has("--defense"):
		for index in actors.size():
			var training = actors[index].get_node("Training")
			training.profile = training.profile.duplicate(true)
			training.profile.tactics.stress_tolerance = 1.5 if index == 1 else 0.15
			if index == 2:
				training.profile.selected_tactics.erase(&"cover")
				training.profile.selected_tactics.erase(&"covering_retreat")
	if OS.get_cmdline_user_args().has("--no-hints"):
		for actor in actors:
			actor.get_node("Training").profile = actor.get_node("Training").profile.duplicate(true)
			actor.get_node("Training").profile.search.tracking_cheat_enabled = false
	if OS.get_cmdline_user_args().has("--handoff"):
		# Unequal frozen inspection durations exercise a real early completion,
		# even when equal-speed members leave the preparation barrier together.
		actors[0].get_node("Training").profile = actors[0].get_node("Training").profile.duplicate(true)
		actors[0].get_node("Training").profile.search.search_pause_seconds = 0.9
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
	if OS.get_cmdline_user_args().has("--normal-cover"):
		await _normal_cover_case()
		scene.queue_free()
		await physics_frame
		print("SQUAD NORMAL COVER: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--defense"):
		await _defense_case()
		scene.queue_free()
		await physics_frame
		print("SQUAD DEFENSE RUNTIME: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--contact-edge"):
		await _contact_edge_case()
		scene.queue_free()
		await physics_frame
		print("SQUAD CONTACT EDGE: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--melee"):
		await _melee_case()
		scene.queue_free()
		await physics_frame
		print("SQUAD MELEE RUNTIME: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
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
	if OS.get_cmdline_user_args().has("--area") and level > 0: await _area_case()
	if level > 0: await _protocol_and_lifecycle()
	scene.queue_free()
	await physics_frame
	if level > 0: await _reload_scene()
	print("SQUAD COMMAND RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _contact_edge_case() -> void:
	# The actual user capture: one eye can see around CoverF, but its muzzle
	# cannot shoot. Never inject the resulting visibility or invalid aim.
	player.global_position = Vector3(18.0703697, 0.0007463, -0.976615)
	var positions := [Vector3(25.4848766, 0, 5.6546197), Vector3(28.964489, 0, 4.6225762), Vector3(31.200674, 0, 1.82772)]
	for index in actors.size():
		actors[index].global_position = positions[index]
		actors[index].look_at(player.global_position)
	var saw_no_aim := false
	var first_shot := -1
	var safe := true
	for frame in 600:
		var shots: Array = actors.map(func(actor): return actor.shot_count)
		await physics_frame
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			if frame < 10 and ai.context.sees_player and not ai.context.last_seen_aim_position.is_finite(): saw_no_aim = true
			if actor.shot_count > shots[index]:
				if first_shot < 0: first_shot = frame
				safe = safe and ai.context.sees_player
	check(saw_no_aim, "Actual first observer sees the target without a usable muzzle aim")
	check(first_shot >= 0 and first_shot < 480, "The squad changes posts and actually fires within eight seconds")
	check(actors.any(func(actor): return actor.global_position.distance_to(positions[actors.find(actor)]) > 1.0), "An unavailable current shot leads to a real reposition")
	check(safe, "Shared feet never authorize a shot without personal sight")
	check(actors.all(func(actor): return actor.get_node("AI").utility_decision_count == 0), "Reposition stays under squad command")
	print("CONTACT EDGE first_shot=", first_shot, " members=", JSON.stringify(actors.map(_trace)))

func _melee_case() -> void:
	var facts := {"hits": {}, "roles": {}, "finished": {}, "windup_frames": 0, "push": false}
	var exclusive := true
	var held := true
	var resumed := false
	for actor in actors:
		actor.look_at(player.global_position)
		actor.melee_struck.connect(func(target, _settings, _direction):
			if target != player: return
			facts.hits[actor.get_instance_id()] = true
			var task: Dictionary = actor.get_node("AI").current_action.command
			facts.roles[task.get("role")] = true)
		actor.melee_finished.connect(func(cancelled):
			if not cancelled: facts.finished[actor.get_instance_id()] = true)
	for frame in 600: await physics_frame
	# Approach each saved ranged member through real player movement. Neither
	# task choice nor visibility, swing phase, hits or completion is injected.
	for target in actors:
		print("MELEE APPROACH ", target.name, " ", JSON.stringify(actors.map(_trace)))
		player.global_position = target.global_position - target.global_basis.z * 1.2
		for frame in 240:
			var before := {}
			for actor in actors:
				var ai = actor.get_node("AI")
				before[actor] = {"phase": ai.context.melee.phase, "shots": actor.shot_count,
					"position": actor.global_position, "task": ai.current_action.command.duplicate() if ai.current_action != null else {}}
			_approach_player(target)
			await physics_frame
			facts.push = facts.push or player._melee_push_remaining > 0.0
			for actor in actors:
				var ai = actor.get_node("AI")
				var sample: Dictionary = before[actor]
				if sample.phase == ai.context.melee.Phase.READY: continue
				exclusive = exclusive and actor.shot_count == sample.shots and not actor.ammo.is_reloading
				if sample.phase == ai.context.melee.Phase.WINDUP:
					facts.windup_frames += 1
					exclusive = exclusive and actor.global_position.distance_to(sample.position) < 0.001
				if actor.melee_active:
					held = held and ai.current_action != null and preload("res://scripts/enemy/services/squad_contract.gd").same_task(sample.task, ai.current_action.command)
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	var starts: Array = actors.map(func(actor): return actor.global_position)
	var shots: Array = actors.map(func(actor): return actor.shot_count)
	player.global_position = arena.to_global(Vector3.ZERO)
	for frame in 180: await physics_frame
	for index in actors.size():
		resumed = resumed or actors[index].shot_count > shots[index] or actors[index].global_position.distance_to(starts[index]) > 0.5
	check(actors.all(func(actor): return actor.can_use_firearms() and actor.weapon.melee_windup_seconds > 0.0), "Saved ranged weapons retain real nonzero melee windup")
	check(facts.hits.size() == actors.size() and facts.push, "Every ranged member actually hits and pushes the approaching player")
	var roles: Array = actors.map(func(actor): return arena.cooperation.coordinator_for(actor.get_node("AI").context)._template.contact_roles.get(actor.get_instance_id()))
	check(roles.has(&"support") and roles.has(&"flank") and roles.has(&"engage") and facts.hits.size() == actors.size(), "All three team specialties retain melee across real post changes")
	check(facts.finished.size() == actors.size() and facts.windup_frames >= 18, "Windup survives multiple frames and every member completes recovery")
	check(exclusive, "No windup movement or simultaneous firearm/reload during melee")
	check(held and resumed, "Melee retains its executing command and normal duties resume afterwards")
	check(actors.all(func(actor): return actor.get_node("AI").utility_decision_count == 0), "Close defense never activates personal Utility")
	print("MELEE RESULT level=", level, " ", facts)
	await _melee_reload_case()
	# Change only instance weapon inputs; live equipment must still veto a
	# frozen battle capability that originally permitted melee.
	for actor in actors:
		actor.weapon = actor.weapon.duplicate(true)
		actor.weapon.melee_enabled = false
	for frame in 30: await physics_frame
	var strikes: Array = actors.map(func(actor): return actor.melee_count)
	var close := {}
	for target in actors:
		player.global_position = target.global_position - target.global_basis.z * 1.2
		for frame in 90:
			_approach_player(target)
			await physics_frame
			var ai = target.get_node("AI")
			if ai.context.sees_player and target.melee_target_reachable(player, ai.context.melee.weapon_settings(), -target.global_basis.z): close[target] = true
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	check(close.size() == actors.size() and strikes == actors.map(func(actor): return actor.melee_count), "Disabled melee weapons never swing despite actual visible front-range approaches")

func _approach_player(target: Node3D) -> void:
	var direction: Vector3 = (target.global_position - player.global_position).normalized()
	Input.action_press("move_right", maxf(0.0, direction.x))
	Input.action_press("move_left", maxf(0.0, -direction.x))
	Input.action_press("move_down", maxf(0.0, direction.z))
	Input.action_press("move_up", maxf(0.0, -direction.z))
	player._physics_process(1.0 / 60.0)

func _melee_reload_case() -> void:
	var target = actors[0]
	target.ammo.magazine_rounds = 0
	var reloading := false
	for frame in 300:
		await physics_frame
		if target.ammo.is_reloading and target.ammo.reload_progress > 0.2:
			reloading = true
			break
	player.global_position = target.global_position - target.global_basis.z * 1.2
	var interrupted := false
	for frame in 120:
		_approach_player(target)
		await physics_frame
		if target.melee_active and not target.ammo.is_reloading:
			interrupted = true
			break
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	player.global_position = arena.to_global(Vector3.ZERO)
	var refilled := false
	var premature := false
	for frame in 360:
		await physics_frame
		var task: Dictionary = target.get_node("AI").context.coordination_assignment()
		premature = premature or task.get("role") == &"reload" and task.get("state") == &"complete" and target.ammo.magazine_rounds == 0
		refilled = refilled or target.ammo.magazine_rounds > 0
	check(reloading and interrupted and refilled and not premature, "Melee interrupts an actual reload, then reload resumes and refills before completion")

func _search_case() -> void:
	var handoff = OS.get_cmdline_user_args().has("--handoff")
	if level == 2:
		_search_audit = {"grouped": true, "ready": true, "held": true, "wait_frames": 0, "hold_frames": 0, "releases": 0, "seen": {}}
		physics_frame.connect(_audit_search_step)
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
	if handoff:
		# An actual second wall keeps the target hidden beyond the first
		# inspection step; all readiness and completion still come from AI.
		var screen := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.3, 3.0, 8.0)
		collision.shape = shape
		screen.add_child(collision)
		arena.add_child(screen)
		screen.global_position = arena.to_global(Vector3(-7.0, 1.5, 1.5))
		player.global_position = arena.to_global(Vector3(-7.6, 0, 1.5))
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
	var search_costs: Array[int] = []
	var peak_cost := 0
	for frame in 900:
		await physics_frame
		var total: int = arena.get("cooperation").last_advance_usec
		for actor in actors:
			for cost in actor.get_node("AI").frame_costs.values(): total += int(cost)
		search_costs.append(total)
		if total > maxi(peak_cost, 16000):
			peak_cost = total
			print("SEARCH COST ", total, " squad=", arena.get_node("Squad").coordinator.frame_costs, " members=", actors.map(func(actor): return actor.get_node("AI").frame_costs))
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
			var overlay = root.get_node("DebugSettings/CoordinatorPaths")
			check(not overlay.coverage_snapshots.is_empty() and overlay.get_node("GroundRoutes").mesh.get_surface_count() > 0, "Map observation snapshots produce actual ground geometry")
			var capture_directory = "res://logs/tactical_search_20261023"
			DirAccess.make_dir_recursive_absolute(capture_directory)
			check(not picture.is_empty() and picture.save_png(capture_directory.path_join("map_observation_routes.png")) == OK, "Rendered world-space command routes are captured")
	check(owned, "Loss, congestion and replanning never return tactical authority to personal Utility")
	check(search_members.size() == actors.size(), "All members actually execute search commands")
	check(stable, "The search objective survives layout changes until a real new contact")
	if not handoff:
		check(reacquired >= 0 and reacquired <= 480, "Saved wall search actually reacquires within the existing eight-second boundary")
	check(closest >= 0.64, "Search preserves physical body separation")
	search_costs.sort()
	check(search_costs[int(search_costs.size() * 0.99)] < 16000 and search_costs[-1] < 50000, "Search preparation and execution keep full-frame P99 <16ms / maximum <50ms")
	if OS.get_cmdline_user_args().has("--blocked-exit"):
		check(reacquired >= 0 and stable and search_members.size() == actors.size(), "A physically blocked cover exit still yields a complete alternative search layout")
	check(hidden_stable and false_completion_rejected, "Hidden movement cannot update the clue; unobserved arrival cannot mark coverage")
	if OS.get_cmdline_user_args().has("--crowded"):
		check(arena.get_node("Squad").coordinator.traffic_wait_count > initial_waits and actors.all(func(actor): return actor.global_position.distance_to(starts[actors.find(actor)]) > 1.0), "Crowded wall approach identifies blockers and all members actually clear the passage")
	if level == 2 and not mixed:
		var squad = arena.get_node("Squad").coordinator
		check(squad.barrier_wait_count > 0 and squad.barrier_release_count > 0, "Strong coordination actually stages and releases participating observers, including the loss transition")
	if level == 2:
		physics_frame.disconnect(_audit_search_step)
		check(_search_audit.grouped, "Every shared search step retains synchronization for all of its searchers")
		check(_search_audit.ready and _search_audit.releases > 0, "Exposure starts only when all participants are physically at preparation posts")
		check(_search_audit.held and _search_audit.wait_frames > 0, "Early arrivals hold their assigned posts while later participants are still travelling")
		if handoff:
			check(_search_audit.hold_frames > 0 and _search_audit.releases >= 2, "Completed observers wait for their peers and subsequent search steps synchronize again")
		print("HANDOFF AUDIT ", JSON.stringify(_search_audit))
	print("SEARCH RESULT reacquired=", reacquired, " min=", closest, " barriers=", barriers_seen.size(), " waits=", barrier_waits, " released=", released, " p99_usec=", search_costs[int(search_costs.size() * 0.99)], " peak_usec=", search_costs[-1], " moved=", actors.map(func(actor): return actor.global_position.distance_to(starts[actors.find(actor)])))

func _audit_search_step() -> void:
	var squad = arena.get_node("Squad").coordinator
	var task_table: Dictionary = squad._tasks
	var objective: Dictionary = squad._objective
	if objective.get("phase") != &"search":
		_search_audit_previous.clear()
		return
	var searchers: Array = task_table.keys().filter(func(id): return task_table[id].role == &"search" and not task_table[id].get("sync_key", "").is_empty())
	if searchers.size() < 2: return
	var grouped = true
	for id in searchers:
		var peers = searchers.filter(func(other): return task_table[other].get("sync_key") == task_table[id].get("sync_key"))
		if peers.size() >= 2:
			grouped = grouped and squad._barriers.values().any(func(barrier): return peers.all(func(peer): return barrier.members.has(peer)))
	for key in squad._barriers:
		var barrier: Dictionary = squad._barriers[key]
		if barrier.released and not _search_audit.seen.has(key):
			_search_audit.seen[key] = true
			_search_audit.releases += 1
			for id in barrier.members:
				var actor = instance_from_id(id)
				_search_audit.ready = _search_audit.ready and actor.global_position.distance_to(task_table[id].staging_position) <= 0.12 + actor.move_speed / 60.0 + 0.001
		if not barrier.released:
			for id in barrier.members:
				if task_table[id].get("reason") == &"staging_barrier": _search_audit.wait_frames += 1
	_search_audit.grouped = _search_audit.grouped and grouped
	if _search_audit_previous.get("objective") == objective.objective_id:
		var previous: Dictionary = _search_audit_previous.tasks
		var failed = previous.values().any(func(task): return task.state in [&"blocked", &"occupied"] or task.expires_at <= squad.elapsed)
		failed = failed or task_table.values().any(func(task): return task.state in [&"blocked", &"occupied"])
		if not failed:
			for id in previous:
				if previous[id].role != &"search" or previous[id].state != &"complete": continue
				var key = previous[id].get("sync_key", "")
				if key.is_empty() or previous[id].get("search_revision") != task_table.get(id, {}).get("search_revision"): continue
				if not previous.values().any(func(task): return task.role == &"search" and task.get("sync_key") == key and task.state != &"complete"): continue
				_search_audit.hold_frames += 1
				_search_audit.held = _search_audit.held and task_table.has(id) and task_table[id].task_id == previous[id].task_id and instance_from_id(id).global_position.distance_to(previous[id].position) <= 0.18
	_search_audit_previous = {"objective": objective.objective_id, "tasks": task_table.duplicate(true)}

func _defense_case() -> void:
	for actor in actors: actor.get_node("AI").set_physics_process(false)
	for frame in 12: await physics_frame
	var tall = OS.get_cmdline_user_args().has("--tall")
	var positions: Array[Vector3] = [Vector3(8.7, 0, -1.0), Vector3(8.7, 0, 1.8), Vector3(5, 0, -3)]
	if tall:
		positions = [Vector3(-1.5, 0, -2.2), Vector3(7, 0, -3.5), Vector3(11, 0, -2.5)]
		player.global_position = arena.to_global(Vector3(3, 0, 0))
	for index in actors.size():
		var desired: Vector3 = arena.to_global(positions[index])
		var ctx = actors[index].get_node("AI").context
		var point = NavigationServer3D.region_get_closest_point(ctx.navigation_region.get_rid(), desired)
		point.y = 0.0
		actors[index].global_position = point
		actors[index].velocity = Vector3.ZERO
		actors[index].look_at(player.global_position)
	for actor in actors: actor.get_node("AI").set_physics_process(true)
	# Damage starts this defense case before ordinary contact has already
	# completed a proactive peek. Perception and all tasks still run normally.
	for frame in 3: await physics_frame
	var start: Vector3 = actors[0].global_position
	var training = actors[0].get_node("Training").profile
	training.tactics.stress_tolerance = 4.0
	var saved = ResourceSaver.save(training, "res://logs/coordinator_repair_20261023/stress_training.tres")
	var reloaded = ResourceLoader.load("res://logs/coordinator_repair_20261023/stress_training.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved == OK and reloaded.tactics.stress_tolerance == 4.0 and actors[0].get_node("AI").context.member_capability_snapshot().stress_tolerance == 0.15, "Training tolerance persists while an assembled battle retains its original value")
	for actor in actors: actor.receive_hit(10.0, player.global_position)
	var low := false
	var high := false
	var untrained := false
	var protected_body := false
	var peek_shot := false
	var returned := false
	var resumed := false
	var owned := true
	var hidden_position := Vector3.INF
	var peak_shots := 0
	var previous_role: StringName = &""
	var renewed_hit := -1
	var return_command := -1
	var supporting_shot := false
	var previous_shots: Array = actors.map(func(actor): return actor.shot_count)
	var minimum := INF
	var costs: Array[int] = []
	for frame in 1200:
		await physics_frame
		var total: int = arena.get("cooperation").last_advance_usec
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			for cost in ai.frame_costs.values(): total += int(cost)
			owned = owned and not task.is_empty() and ai.utility_decision_count == 0
			if index == 1: high = high or task.get("role") in [&"shelter", &"cover_peek"] and not task.get("defense_proactive", false)
			if index == 2: untrained = untrained or task.get("role") in [&"shelter", &"cover_peek"]
			if index > 0 and task.get("role") == &"support" and actors[0].get_node("AI").context.coordination_assignment().get("role") in [&"shelter", &"cover_peek"]:
				supporting_shot = supporting_shot or actor.shot_count > previous_shots[index] and ai.context.sees_player
			previous_shots[index] = actor.shot_count
			for other in actors.slice(index + 1): minimum = minf(minimum, actor.global_position.distance_to(other.global_position))
		var ctx = actors[0].get_node("AI").context
		var task: Dictionary = ctx.coordination_assignment()
		if task.get("role") == &"shelter":
			low = true
			if renewed_hit >= 0 and return_command < 0: return_command = frame
			if actors[0].global_position.distance_to(task.position) <= 0.18:
				var post: Dictionary = task.defense_post
				var hidden: bool = preload("res://scripts/enemy/services/squad_defense.gd").protected(ctx, post, player.global_position)
				protected_body = protected_body or hidden and (not post.crouch or actors[0].is_crouching())
				if hidden: hidden_position = actors[0].global_position
				returned = returned or peek_shot and hidden and (not post.crouch or actors[0].is_crouching())
		elif task.get("role") == &"cover_peek":
			if peak_shots == 0: peak_shots = actors[0].shot_count
			peek_shot = peek_shot or actors[0].shot_count > peak_shots and ctx.sees_player and not actors[0].is_crouching()
			if tall and peek_shot and renewed_hit < 0:
				renewed_hit = frame
				actors[0].receive_hit(10.0, player.global_position)
		elif returned and task.get("role") in [&"engage", &"support", &"flank", &"search"]: resumed = true
		costs.append(total)
		if frame % 180 == 0 or task.get("role") != previous_role: print("DEFENSE TRACE ", frame, " ", JSON.stringify(actors.map(_trace)), " request=", ctx.coordination_debug_snapshot().get("defense"))
		previous_role = task.get("role", &"")
	check(low and not high, "Equal damage triggers low-tolerance defense, without forcing high-tolerance defense; normal tactical cover stays eligible")
	check(not untrained, "Pressure cannot unlock an untrained cover action")
	check(protected_body and hidden_position.is_finite(), "Member actually reaches protection and crouches behind low cover when required")
	check(peek_shot and returned and resumed, "Cover sequence actually peeks, fires, returns to protection and resumes squad duties")
	check(owned and minimum >= 0.64, "Defense preserves continuous squad ownership, zero personal Utility and physical separation")
	check(supporting_shot, "An eligible teammate actually fires with personal sight while the threatened member uses cover")
	if tall: check(renewed_hit >= 0 and return_command > renewed_hit and return_command - renewed_hit <= 30, "Renewed actual damage during peek promptly restores the assigned shelter step")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Defense keeps original full-frame P99 <16ms / maximum <50ms budget")
	print("DEFENSE RESULT tall=", tall, " moved=", actors[0].global_position.distance_to(start), " protected=", protected_body, " peek=", peek_shot, " returned=", returned, " resumed=", resumed, " p99=", costs[int(costs.size() * 0.99)], " max=", costs[-1])

func _normal_cover_case() -> void:
	for actor in actors: actor.get_node("AI").set_physics_process(false)
	for frame in 12: await physics_frame
	var positions := [Vector3(8.7, 0, -1.0), Vector3(8.7, 0, 1.8), Vector3(5, 0, -3)]
	for index in actors.size():
		var ctx = actors[index].get_node("AI").context
		var point := NavigationServer3D.region_get_closest_point(ctx.navigation_region.get_rid(), arena.to_global(positions[index]))
		point.y = 0.0
		actors[index].global_position = point
		actors[index].velocity = Vector3.ZERO
		actors[index].look_at(player.global_position)
		actors[index].get_node("AI").set_physics_process(true)
	var hide := {}
	var fired := {}
	var returned := {}
	var owned := true
	var costs: Array[int] = []
	var old_shots: Array = actors.map(func(actor): return actor.shot_count)
	for frame in 1200:
		await physics_frame
		var cost: int = arena.get("cooperation").last_advance_usec
		for index in actors.size():
			var actor = actors[index]
			var ctx = actor.get_node("AI").context
			var task: Dictionary = ctx.coordination_assignment()
			owned = owned and not task.is_empty() and actor.get_node("AI").utility_decision_count == 0
			for value in actor.get_node("AI").frame_costs.values(): cost += int(value)
			if task.get("defense_proactive", false):
				if task.role == &"shelter" and actor.global_position.distance_to(task.position) <= 0.18:
					if preload("res://scripts/enemy/services/squad_defense.gd").protected(ctx, task.defense_post, player.global_position):
						hide[index] = true
						if fired.has(index): returned[index] = true
				if task.role == &"cover_peek" and actor.shot_count > old_shots[index] and ctx.sees_player: fired[index] = true
			old_shots[index] = actor.shot_count
		costs.append(cost)
		if frame % 180 == 0: print("NORMAL COVER TRACE ", frame, " ", JSON.stringify(actors.map(_trace)))
	check(not hide.is_empty(), "Normal contact selects trained cover and physically reaches shelter without a damage trigger")
	check(not fired.is_empty() and not returned.is_empty(), "Normal cover actually peeks, fires through personal sight, then returns")
	check(owned, "Normal cover preserves squad ownership and zero personal Utility")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Normal cover keeps the original whole-team frame budget")
	print("NORMAL COVER RESULT hide=", hide, " fired=", fired, " returned=", returned, " p99=", costs[int(costs.size() * 0.99)], " peak=", costs[-1])

func _area_case() -> void:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 3.0, 8.0)
	collision.shape = box
	wall.add_child(collision)
	arena.add_child(wall)
	wall.position = Vector3(-7.0, 1.5, 1.5)
	player.global_position = arena.to_global(Vector3(-7.6, 0, 1.5))
	if OS.get_cmdline_user_args().has("--no-hints"):
		# A single screen can be flanked by the new map-wide route. Keep this
		# sixty-second observation case genuinely hidden with an opaque enclosure;
		# saved-wall reacquisition is tested separately. Stay in the active arena.
		player.global_position = arena.to_global(Vector3(-7.6, 0, 1.5))
		for side in [-1.0, 1.0]:
			for axis in [0, 2]:
				var screen := StaticBody3D.new()
				var shape_node := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(0.2, 3.0, 1.4) if axis == 0 else Vector3(1.4, 3.0, 0.2)
				shape_node.shape = shape
				screen.add_child(shape_node)
				arena.add_child(screen)
				var offset := Vector3(-7.6, 1.5, 1.5)
				offset[axis] += side * 0.6
				screen.position = offset
	var squad = arena.get_node("Squad").coordinator
	var observed := 0
	var late_motion := 0
	var idle := 0
	var max_idle := 0
	var bounded := true
	var beyond_initial := false
	var future_routes := false
	var moving_observation := false
	var last_area := 0.0
	var independent: Array[Vector3] = []
	var independent_seen := {}
	var independent_late := false
	var sample_ctx = actors[0].get_node("AI").context
	# Independent, denser grid, actual floor and rays; do not use ledger points
	# or its observed flags as the proof that new map area was inspected.
	for x in range(-10, 11):
		for z in range(-7, 8):
			var point: Vector3 = arena.to_global(Vector3(x * 0.9, 0, z * 0.9))
			var nav := NavigationServer3D.region_get_closest_point(sample_ctx.navigation_region.get_rid(), point)
			if Vector2(nav.x - point.x, nav.z - point.z).length() > 0.15: continue
			if preload("res://scripts/systems/character_geometry.gd").can_occupy(actors[0], point, 0.8, 0.15, true): independent.append(point)
	var owned := true
	var frozen := Vector3.INF
	var reacquired := -1
	var last_positions: Array = actors.map(func(actor): return actor.global_position)
	var area_costs: Array[int] = []
	var area_peak := 16000
	for frame in 3600:
		await physics_frame
		var total: int = arena.get("cooperation").last_advance_usec
		for actor in actors:
			for cost in actor.get_node("AI").frame_costs.values(): total += int(cost)
		area_costs.append(total)
		if total > area_peak:
			area_peak = total
			print("AREA PEAK ", frame, " total=", total, " squad=", squad.frame_costs, " members=", actors.map(func(actor): return actor.get_node("AI").frame_costs))
		if squad._objective.get("phase") != &"search":
			if frozen.is_finite() and reacquired < 0 and actors.any(func(actor): return actor.get_node("AI").context.sees_player): reacquired = frame
			continue
		if not frozen.is_finite(): frozen = squad._objective.position
		owned = owned and squad._objective.position == frozen
		var moved := false
		for index in actors.size():
			var actor = actors[index]
			var ctx = actor.get_node("AI").context
			var task: Dictionary = ctx.coordination_assignment()
			owned = owned and not task.is_empty() and actor.get_node("AI").utility_decision_count == 0
			if actor.global_position.distance_to(last_positions[index]) > 0.005: moved = true
			last_positions[index] = actor.global_position
			if task.has("coverage_key"):
				var nav := NavigationServer3D.region_get_closest_point(ctx.navigation_region.get_rid(), task.position)
				bounded = bounded and Vector2(nav.x - task.position.x, nav.z - task.position.z).length() < 0.7
				beyond_initial = beyond_initial or ctx._horizontal_distance_between(actor.global_position, squad._search.origin) > squad._search.settings.get("search_radius", 5.0) + 1.0
				future_routes = future_routes or not task.get("future_steps", []).is_empty()
		if frame > 1800 and moved: late_motion += 1
		idle = 0 if moved else idle + 1
		max_idle = maxi(idle, max_idle)
		if idle == 180:
			print("AREA IDLE ", frame, " ", actors.map(_trace), " observation=", squad._observations)
		observed = maxi(observed, squad._search.snapshot().observed)
		var area: float = squad._search.snapshot(squad.elapsed).observed_area
		moving_observation = moving_observation or moved and area > last_area
		last_area = area
		if frame % 12 == 0:
			for index in independent.size():
				if independent_seen.has(index): continue
				for actor in actors:
					var point: Vector3 = independent[index]
					var offset: Vector3 = point - actor.global_position
					var perception = actor.get_node("AI").context.perception
					if offset.length() > perception.sight_distance: continue
					offset.y = 0.0
					if not offset.is_zero_approx() and (-actor.global_basis.z).dot(offset.normalized()) < cos(deg_to_rad(perception.sight_angle_degrees * 0.5)): continue
					var visible := true
					for height in [0.4, 1.1]:
						var query := PhysicsRayQueryParameters3D.create(actor.get_eye_position(), point + Vector3.UP * height, 1, [actor.get_rid(), player.get_rid()])
						if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): visible = false
					if visible:
						independent_seen[index] = frame
						if frame > 1800: independent_late = true
						break
	check(owned and bounded, "Long hidden search retains ownership, true last sight and navigation-region bounds")
	if OS.get_cmdline_user_args().has("--no-hints"):
		check(observed >= 10 and late_motion > 120, "Real observation covers the region and search still progresses after thirty seconds")
		check(beyond_initial and future_routes and moving_observation, "Continuous observation routes extend past the initial search radius while moving")
		check(independent_seen.size() >= independent.size() * 0.65 and independent_late, "Independent hiding-space rays confirm broad map coverage and new late progress")
	else:
		check(reacquired > 0 and reacquired <= 480, "Uncertain squad hints lead to actual reacquisition within eight seconds")
	check(max_idle < 240, "No all-member observation deadlock lasts four seconds")
	area_costs.sort()
	check(area_costs[int(area_costs.size() * 0.99)] < 16000 and area_costs[-1] < 50000, "Full-map observation and continuous planning retain the original 16/50ms frame limits")
	var hints = squad._search.snapshot()
	check(hints.hint_checks == 0 if OS.get_cmdline_user_args().has("--no-hints") else hints.hint_checks > 0 and not hints.hint.is_empty(), "Squad hint lifecycle obeys the frozen Training switch")
	print("AREA RESULT ", hints, " max_idle=", max_idle, " late_motion=", late_motion, " observed_peak=", observed, " members=", actors.map(_trace))
	print("INDEPENDENT AREA ", independent_seen.size(), "/", independent.size(), " beyond=", beyond_initial, " future=", future_routes, " moving=", moving_observation, " late=", independent_late)
	print("AREA COST p99=", area_costs[int(area_costs.size() * 0.99)], " peak=", area_costs[-1])

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
	var area_before: Dictionary = squad._search.coverage.cells.duplicate(true)
	var queries_before: int = ai.context.cover_selection.environment_ray_queries
	for repeat in 30:
		var snapshot: Dictionary = ai.context.coordination_debug_snapshot()
		snapshot.get("task", {}).clear()
		var map_snapshot: Dictionary = ai.context.observation_debug_snapshot()
		map_snapshot.get("display", []).clear()
	check(before == squad._tasks, "Debug reads and caller edits cannot alter live tasks")
	check(area_before == squad._search.coverage.cells and queries_before == ai.context.cover_selection.environment_ray_queries, "Coverage debug reads neither mutate observations nor cast new visibility rays")
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
	if not occupied or not reloaded:
		print("RELOAD DIAG ", actors[0].ammo.magazine_rounds, " / ", actors[0].ammo.reload_progress, " ", JSON.stringify(actors.map(_trace)))
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
	if actors[0].shot_count == shots and actors[0].global_position.distance_to(start) <= 0.5:
		print("SURVIVOR FIRE ", ai.context.member_runtime_snapshot(), " aim=", ai.context.last_seen_aim_position,
			" direction=", actors[0].aim_direction, " muzzle=", actors[0].get_shot_origin(), " ready=", actors[0].can_fire(),
			" fire=", ai.context.fire.request, " pause=", ai.context.fire.fire_pause_remaining, " interval=", ai.context.fire.fire_interval_remaining,
			" decision=", ai.context.fire.fire_decision.selected_action, " task=", ai.context.coordination_assignment())
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
