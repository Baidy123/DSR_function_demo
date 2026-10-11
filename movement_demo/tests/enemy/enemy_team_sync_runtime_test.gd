extends "res://tests/enemy/enemy_cover_inspection_test.gd"

const TrainingFixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var suspended_actor := -1

func _run() -> void:
	var modes: Array[String] = ["late", "blocked", "self_preservation"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="): modes.assign([argument.trim_prefix("--mode=")])
	for mode: String in modes: await _bounded_case(mode)
	print("TEAM SYNC RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _tick() -> void:
	await physics_frame
	for index in actors.size():
		if index != suspended_actor: actors[index].get_node("AI")._physics_process(STEP)

func _bounded_case(mode: String) -> void:
	suspended_actor = -1
	seed(20261011)
	await _setup(true)
	for actor in actors:
		TrainingFixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
		actor.get_node("AI").set_physics_process(false)
	for frame in 4: await _tick()
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	check(actors.all(func(actor): return not actor.get_node("AI").context.sees_player), "%s case starts from real loss of sight" % mode)
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var original: Dictionary = {}
	var affected := -1
	var cleared_at := -1.0
	var duplicate_wait := false
	var released_without_ready := false
	var local_recovery := false
	var changed_plans: Array = []
	var trace: Array = []
	for frame in 720:
		await _tick()
		if original.is_empty():
			for index in actors.size():
				var task: Dictionary = actors[index].get_node("AI").context.coordination_assignment()
				if not task.get("accepted", false) or task.get("role", &"") not in [&"inspect_left", &"inspect_right"]: continue
				if task.get("phase") == &"executing": continue
				original = task.duplicate(true)
				affected = index
				if mode == "late": suspended_actor = index
				elif mode == "blocked":
					var blocker := _box(Vector3.ZERO, Vector3(1.1, 3.0, 1.1), false)
					arena.add_child(blocker)
					blocker.global_position = task.staging_position + Vector3.UP * 1.5
				else:
					# Actual empty ammunition is a real body condition; Utility still
					# chooses whether and how to execute its legal reload escape.
					actors[index].ammo.magazine_rounds = 0
				break
		if affected >= 0:
			var ai = actors[affected].get_node("AI")
			var task: Dictionary = ai.context.coordination_assignment()
			if task.is_empty() or task.assignment_id != original.assignment_id:
				if cleared_at < 0.0: cleared_at = arena.cooperation.elapsed
			if not task.is_empty() and task.plan_id != original.plan_id:
				if not changed_plans.has(task.plan_id): changed_plans.append(task.plan_id)
				if cleared_at >= 0.0 and arena.cooperation.elapsed - cleared_at < 1.9 and task.get("reserved_position_sets", []) == original.get("reserved_position_sets", []): duplicate_wait = true
			if mode == "late":
				released_without_ready = released_without_ready or (not task.is_empty() and task.assignment_id == original.assignment_id and task.phase == &"executing")
			if mode == "self_preservation": local_recovery = local_recovery or (ai.utility_current.get("id", &"") == &"reload" and actors[affected].ammo.is_reloading and task.is_empty())
			if frame % 30 == 0: trace.append({"frame": frame, "time": arena.cooperation.elapsed, "actor": affected, "action": ai.utility_current.get("id", &""), "assignment": task.get("assignment_id", 0), "plan": task.get("plan_id", 0), "phase": task.get("phase", &""), "position": actors[affected].global_position})
			if cleared_at >= 0.0 and arena.cooperation.elapsed - cleared_at >= 2.1: break
	check(not original.is_empty(), "%s intervention follows a real autonomously accepted inspection assignment" % mode)
	check(cleared_at >= 0.0 and cleared_at <= float(original.get("expires_at", -INF)) + 0.1, "%s releases the unavailable commitment within its original finite deadline" % mode)
	check(not duplicate_wait, "%s does not immediately recreate the same failed actor/position wait in a fresh plan" % mode)
	if mode == "late": check(not released_without_ready, "A late participant never releases the shared segment using stale or absent readiness")
	if mode == "self_preservation": check(local_recovery, "The empty actor autonomously executes a real reload after releasing its team commitment")
	print("TEAM SYNC TRACE mode=", mode, " original=", JSON.stringify(original), " cleared_at=", cleared_at, " new_plans=", changed_plans, " ", JSON.stringify(trace))
	suspended_actor = -1
	scene.queue_free()
	await physics_frame
