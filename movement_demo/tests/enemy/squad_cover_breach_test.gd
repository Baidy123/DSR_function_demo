extends SceneTree

## Saved arena, original perception/AI/body/fire loops. Only initial fixture
## equipment, training and speed differ; no injected commands or ready facts.
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	var modes: Array[StringName] = [&"hold", &"delayed_overwatch", &"escape", &"death", &"reload", &"cover_changed", &"blocked", &"support_reload"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): modes = modes.filter(func(mode): return mode == StringName(arg.trim_prefix("--case=")))
	check(not modes.is_empty(), "At least one cover breach scenario is selected")
	for mode in modes:
		await _runtime(mode)
	print("SQUAD COVER BREACH: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _runtime(mode: StringName) -> void:
	print("COVER BREACH CASE ", mode)
	var preserve: bool = mode in [&"hold", &"delayed_overwatch"]
	seed(20261027)
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var squad = arena.get_node("Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = 2
	var actors: Array = squad.get_children().filter(func(actor): return actor.has_node("AI"))
	check(actors.size() == 3, "Saved arena supplies three real members")
	if actors.size() != 3:
		scene.free()
		return
	var starts := [Vector3(4, 0, 4.0), Vector3(1, 0, -1), Vector3(2, 0, -2.5)]
	for index in actors.size():
		var actor = actors[index]
		actor.position = starts[index]
		actor.weapon = WeaponData.new()
		actor.weapon.magazine_capacity = 1000
		actor.weapon.aim_range = 20.0
		var training = actor.get_node("Training")
		training.profile = training.profile.duplicate(true)
		training.profile.selected_tactics.clear()
		if index == 2: training.profile.selected_tactics.append(&"suppression")
		training.profile.search.tracking_cheat_enabled = false
		training.profile.perception.sight_distance = 30.0
	root.add_child(scene)
	current_scene = scene
	if root.has_node("DebugSettings"): root.get_node("DebugSettings").enabled = false
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get("combat").set_physics_process(false)
	player.get("health").debug_invincible = true
	player.global_position = arena.to_global(Vector3.ZERO)
	for index in actors.size():
		actors[index].move_speed = [1.2, 2.5, 4.0][index]
		actors[index].look_at(player.global_position)
	if mode == &"delayed_overwatch": actors[2].move_speed = 1.3
	for frame in 90: await physics_frame
	check(actors.all(func(actor): return actor.get_node("AI").context.sees_player), "All members acquire the player through real perception")
	for point in [Vector3(-4.84, 0, -1.9), Vector3(-4.84, 0, 0.68)]:
		while player.global_position.distance_to(arena.to_global(point)) > 0.01:
			player.global_position = player.global_position.move_toward(arena.to_global(point), 0.08)
			await physics_frame
	var pending := {}
	var seen_pair := false
	var sight_while_preparing := 0
	var cancellations := 0
	var held_frames := 0
	var released := false
	var ready := true
	var advanced := {}
	var released_tasks := {}
	var owned := true
	var initial_support_shots: int = actors[2].shot_count
	var interrupted_at := -1
	var interrupted_key := 0
	var interrupted := false
	var contact_frames := 0
	var costs: Array[int] = []
	var minimum_gap := INF
	var released_without_support := false
	for frame in 540:
		await physics_frame
		var board = squad.coordinator
		if mode == &"support_reload" and interrupted_at >= 0 and actors[2].ammo.is_reloading:
			released_without_support = released_without_support or board._barriers.get(interrupted_key, {}).get("released", false)
		var total: int = arena.get("cooperation").last_advance_usec
		for actor in actors:
			for cost in actor.get_node("AI").frame_costs.values(): total += int(cost)
		costs.append(total)
		for index in actors.size():
			for other in actors.slice(index + 1):
				if not actors[index].is_dead and not other.is_dead: minimum_gap = minf(minimum_gap, actors[index].global_position.distance_to(other.global_position))
		owned = owned and actors.filter(func(actor): return not actor.is_dead).all(func(actor): return actor.get_node("AI").utility_decision_count == 0 and not actor.get_node("AI").context.coordination_assignment().is_empty())
		if not pending.is_empty():
			var live: Dictionary = board._barriers.get(pending.key, {})
			if live.is_empty() and (board._objective.get("phase") == &"contact" or mode == &"delayed_overwatch"):
				cancellations += 1
				print("BREACH CANCEL time=", board.elapsed, " phase=", board._objective.phase)
			pending.clear()
		for key in board._barriers.keys():
			var barrier: Dictionary = board._barriers[key]
			if barrier.members.size() < 2: continue
			var first: Dictionary = board._tasks[barrier.members[0]]
			if not first.get("sync_key", "").begins_with("cover:"): continue
			seen_pair = true
			if barrier.released:
				if released_tasks.is_empty():
					for id in barrier.members:
						var actor = instance_from_id(id)
						var task: Dictionary = board._tasks[id]
						ready = ready and actor.global_position.distance_to(task.staging_position) <= 0.12 + actor.move_speed / 60.0 + 0.001
						released_tasks[id] = task.duplicate(true)
				released = true
				pending.clear()
			else:
				pending = {"key": key}
				if actors[2].get_node("AI").context.sees_player:
					sight_while_preparing += 1
					var near_entry: bool = actors[0].global_position.distance_to(board._tasks[actors[0].get_instance_id()].staging_position) < 0.25
					if not preserve and interrupted_at < 0 and (mode != &"support_reload" or near_entry):
						interrupted_at = frame
						interrupted_key = key
						match mode:
							&"escape": player.global_position = arena.to_global(Vector3(0, 0, -2))
							&"death": actors[0].receive_hit(actors[0].max_health + 1.0)
							&"reload": check(actors[0].request_reload(), "A participant starts an actual weapon reload")
							&"support_reload": check(actors[2].request_reload(), "Overwatch starts an actual reload immediately before joint readiness")
							&"cover_changed":
								var cover = instance_from_id(int(first.sync_key.trim_prefix("cover:")))
								cover.get_node("CollisionShape3D").disabled = true
							&"blocked":
								var obstacle := StaticBody3D.new()
								var collision := CollisionShape3D.new()
								collision.shape = BoxShape3D.new()
								collision.shape.size = Vector3(1.6, 2.2, 1.6)
								obstacle.add_child(collision)
								arena.add_child(obstacle)
								obstacle.global_position = board._tasks[actors[0].get_instance_id()].staging_position + Vector3.UP * 1.1
				for id in barrier.members:
					if board._tasks.get(id, {}).get("reason") == &"staging_barrier": held_frames += 1
		for id in released_tasks:
			var task: Dictionary = released_tasks[id]
			var direction: Vector3 = (task.position - task.staging_position).normalized()
			if (instance_from_id(id).global_position - task.staging_position).dot(direction) > 0.3: advanced[id] = true
		if interrupted_at >= 0:
			interrupted = interrupted or not board._barriers.has(interrupted_key) and board._objective.get("phase") == &"contact"
			if interrupted: contact_frames += 1
			if contact_frames >= 30: break
		elif preserve and advanced.size() >= 2 and actors[2].shot_count > initial_support_shots: break
		if frame % 120 == 0:
			print("BREACH TRACE frame=", frame, " phase=", board._objective.get("phase"), " tasks=", board._tasks.values().map(func(task): return [task.member_id, task.role, task.state, task.get("reason"), task.get("barrier_id", 0)]))
	check(seen_pair, "Saved left cover receives a real two-sided search step")
	check(sight_while_preparing > 0, "Overwatch really sees the player before both inspectors are ready")
	if preserve:
		check(cancellations == 0, "New overwatch sight does not cancel the pending valid paired step")
		check(held_frames > 0, "Early inspector physically waits for the other side")
		check(released and ready, "Both real preparation posts are reached before release")
		check(advanced.size() >= 2, "Both inspectors physically advance past preparation after release")
	else:
		check(interrupted_at >= 0 and interrupted, "An escaped target or invalid participant/cover cancels the old entry and resumes contact: %s" % mode)
		if mode == &"support_reload": check(not released_without_support, "One inspector cannot release the group while another still lacks required support")
	var support_shots: int = actors[2].shot_count - initial_support_shots
	if preserve: check(support_shots > 0, "Overwatch can still fire through the original weapon loop")
	check(owned, "All members remain commanded without personal Utility")
	check(minimum_gap >= 0.64, "Original body collision clearance remains intact")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Original full-frame P99 <16ms / maximum <50ms budget")
	print("COVER BREACH AUDIT sight_frames=", sight_while_preparing, " cancellations=", cancellations, " held_frames=", held_frames, " shots=", support_shots, " min_gap=", minimum_gap, " p99_usec=", costs[int(costs.size() * 0.99)], " peak_usec=", costs[-1])
	scene.queue_free()
	await physics_frame
