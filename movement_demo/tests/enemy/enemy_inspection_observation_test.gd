extends "res://tests/enemy/enemy_team_inspection_runtime_test.gd"

func _run() -> void:
	for permanent in [false, true]: await _blocked_observation(permanent)
	print("INSPECTION OBSERVATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _blocked_observation(permanent: bool) -> void:
	seed(20261011)
	await _setup(true)
	# Register the body before planning, so the intervention does not change
	# membership or invalidate an otherwise legitimate assignment identity.
	var blocker = load("res://scenes/enemy/enemy.tscn").instantiate()
	blocker.weapon = WeaponData.new()
	blocker.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	blocker.position = Vector3(6, 0, 4)
	arena.add_child(blocker)
	blocker.get_node("AI").set_physics_process(false)
	for actor in actors:
		TrainingFixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
	for frame in 12: await physics_frame
	for frame in 4: await _tick()
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	var evidence: Dictionary = actors[0].get_node("AI").context.cover_inspection_evidence()
	check(not evidence.is_empty(), "Observation fixture obtains a real frozen cover clue")
	if evidence.is_empty():
		scene.queue_free()
		await physics_frame
		return
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var observed: Dictionary = {}
	var original: Dictionary = {}
	var affected := -1
	var blocked_at := -1.0
	var cleared := false
	var premature := false
	var dropped_at := -1.0
	var real_block := false
	var fixed := true
	for frame in 720:
		await physics_frame
		for actor in actors:
			actor.get_node("AI")._physics_process(STEP)
			_record_inspection(observed, actor, frame, evidence.position)
		if affected < 0:
			for index in actors.size():
				var search = actors[index].get_node("AI").actions[&"search"]
				var task: Dictionary = actors[index].get_node("AI").context.coordination_assignment()
				if task.get("accepted", false) and search._inspection_phase == search.InspectionPhase.OBSERVE:
					affected = index
					original = task.duplicate(true)
					blocked_at = arena.cooperation.elapsed
					blocker.global_position = actors[index].global_position.lerp(evidence.position, 0.6)
					break
		elif affected >= 0:
			var context = actors[affected].get_node("AI").context
			var task: Dictionary = context.coordination_assignment()
			var age: float = arena.cooperation.elapsed - blocked_at
			if not task.is_empty() and task.plan_id == original.plan_id: fixed = fixed and task.expires_at == original.expires_at
			if not cleared:
				real_block = real_block or not context.perception.can_observe_position(evidence.position)
				premature = premature or task.get("complete", false)
			if task.get("plan_id", 0) != original.plan_id and dropped_at < 0.0: dropped_at = arena.cooperation.elapsed
			if not permanent and not cleared and age >= 0.8:
				premature = premature or dropped_at >= 0.0
				blocker.global_position = arena.to_global(Vector3(6, 0, 4))
				cleared = true
			if permanent and dropped_at >= 0.0: break
			if not permanent and observed.get(original.plan_id, {}).get("completed", {}).size() == 2: break
	check(affected >= 0 and real_block, "A real friendly capsule occludes an autonomously reached inspection point")
	check(not premature and fixed, "Blocked observation neither invents completion nor renews the original deadline")
	if permanent:
		check(dropped_at >= 0.0 and dropped_at - blocked_at <= 2.1 and dropped_at <= original.get("expires_at", -INF), "A permanent friendly obstruction releases the plan within the finite observation recovery window")
	else:
		check(cleared and observed.get(original.get("plan_id", 0), {}).get("completed", {}).size() == 2, "After the friendly body passes, both actual reports complete in the original plan")
	scene.queue_free()
	await physics_frame
