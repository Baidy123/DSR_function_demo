extends "res://tests/enemy/enemy_search_formation_fallback_test.gd"

func _run() -> void:
	if OS.get_cmdline_user_args().has("--shared-contact"):
		await _shared_contact_case()
		print("STRONG SHARED CONTACT: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	_setup_saved_combat()
	await _continuity_case()

func _setup_saved_combat() -> void:
	seed(20261021)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3.ZERO)
	actors = Fixture.members(arena)
	_use_strong_saved_squad()
	for actor in actors: actor.look_at(player.global_position)

func _shared_contact_case() -> void:
	_setup_saved_combat()
	var starts: Array = actors.map(func(actor): return actor.global_position)
	var receivers: Array[int] = []
	var first_seen := [-1, -1, -1]
	var visible_shot := [-1, -1, -1]
	var last_shots := [0, 0, 0]
	var blind_hold := [0, 0, 0]
	var longest := [0, 0, 0]
	var moved := [0.0, 0.0, 0.0]
	var initial_witnesses := -1
	for frame in 1200:
		await physics_frame
		if initial_witnesses < 0 and actors.any(func(actor): return actor.get_node("AI").context.sees_player):
			initial_witnesses = 0
			for index in actors.size():
				var context = actors[index].get_node("AI").context
				if context.sees_player: initial_witnesses += 1
				elif context.team_visual_contact: receivers.append(index)
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var visible: bool = ai.context.sees_player
			var post: bool = ai.current_action != null and ai.current_action.action_id == &"cooperate" and ai.current_action.plan.get("destination", {}).get("observation_post", false)
			if post and not visible:
				blind_hold[index] += 1
				longest[index] = maxi(longest[index], blind_hold[index])
			else: blind_hold[index] = 0
			if visible and first_seen[index] < 0: first_seen[index] = frame
			if visible and actor.shot_count > last_shots[index] and visible_shot[index] < 0: visible_shot[index] = frame
			last_shots[index] = actor.shot_count
			moved[index] = maxf(moved[index], actor.global_position.distance_to(starts[index]))
	check(initial_witnesses == 1 and receivers.size() == 2, "Saved-map combat starts with one witness and two members receiving only shared sight")
	# Allow the frame boundary between perception and action updates, not a lease
	# of blind standing. Actual sight and shots are checked separately below.
	check(longest.all(func(frames): return frames <= 2), "No member stays bound to a blind observation post")
	check(receivers.size() == 2 and receivers.all(func(index): return moved[index] > 0.5 and first_seen[index] >= 0), "Both initially occluded members actually move and see the target within 20 seconds")
	check(receivers.size() == 2 and receivers.all(func(index): return visible_shot[index] >= first_seen[index] and visible_shot[index] >= 0), "Both receivers fire with their own sight; blind suppression does not count as engagement")
	print("SHARED CONTACT first_seen=", first_seen, " visible_shot=", visible_shot, " max_displacement=", moved, " blind_hold=", longest)
	scene.queue_free()
	await physics_frame

func _continuity_case() -> void:
	var samples := 0
	var assigned := 0
	var accepted := 0
	var gaps := {}
	var longest := {}
	var history: Array = []
	var participants := {}
	for frame in 600:
		await physics_frame
		if frame < 60: continue
		for actor in actors:
			var ai = actor.get_node("AI")
			var context = ai.context
			if not context.is_alerted or actor.is_dead: continue
			var id: int = actor.get_instance_id()
			var task: Dictionary = context.coordination_assignment()
			var emergency: bool = ai.current_action != null and ai.current_action.assignment_escape(ai.utility_current, context.sees_player)
			if emergency or actor.is_vaulting() or actor.melee_active: continue
			samples += 1
			if not task.is_empty(): assigned += 1
			var executing: bool = task.get("accepted", false) and ai.current_action != null and ai.current_action.action_id == task.get("owner_action") and context.coordination_continuation(ai.current_action.execution_contract(context.sees_player), ai.current_action.action_id)
			if executing:
				accepted += 1
				participants[id] = true
				gaps[id] = 0
			else: gaps[id] = int(gaps.get(id, 0)) + 1
			longest[id] = maxi(int(longest.get(id, 0)), int(gaps[id]))
		if frame % 15 == 0: history.append(actors.map(_trace_member))
	check(samples > 900 and participants.size() == actors.size(), "All saved-map members actually accept team duties through their own Utility")
	check(accepted >= samples * 0.85, "Team duties execute for at least 85 percent of active non-emergency combat time")
	check(longest.values().all(func(value): return value <= 60), "No capable member is silently unassigned for longer than the existing one-second acceptance window")
	check(actors.any(func(actor): return actor.shot_count > 0), "Continuous coordination retains actual live fire")
	print("CONTINUITY COVERAGE samples=", samples, " assigned=", assigned, " accepted=", accepted, " longest=", longest)
	if failures: print("CONTINUITY HISTORY ", JSON.stringify(history))
	scene.queue_free()
	await physics_frame
	print("TEAM CONTINUITY RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _trace_member(actor) -> Dictionary:
	var ai = actor.get_node("AI")
	var result: Dictionary = ai.context.coordination_debug_snapshot()
	var task: Dictionary = ai.context.coordination_assignment()
	result.owner = task.get("owner_action", &"")
	result.offers = ai.utility_options.map(func(candidate): return {"id": candidate.get("id"), "role": candidate.get("coordination_role"), "matches": task.get("allowed_offer_keys", []).has(candidate.get("coordination_offer_key", "")), "valid": ai.actions[candidate.id].validate(candidate, ai.context.sees_player)})
	result.visible = ai.context.sees_player
	result.reloading = actor.ammo.is_reloading
	return result
