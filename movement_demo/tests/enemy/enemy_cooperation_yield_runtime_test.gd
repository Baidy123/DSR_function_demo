extends "res://tests/enemy/enemy_cooperation_flank_runtime_test.gd"

func _run() -> void:
	var fixture: Dictionary = await _fixture(2, true)
	for actor in fixture.actors:
		var weapon: WeaponData = actor.weapon.duplicate(true)
		weapon.magazine_capacity = 60
		actor.equip_weapon(weapon)
	var original: Dictionary = {}
	var mover
	var origin := Vector3.INF
	var correction_seconds := 0.0
	var displaced := 0.0
	var canceled := false
	var fixed_deadline := true
	var completed := false
	for frame in 1080:
		await physics_frame
		for actor in fixture.actors:
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var task: Dictionary = ai.context.coordination_assignment()
			var action = ai.actions[&"cooperate"]
			if original.is_empty() and task.get("accepted", false) and task.role == &"flank" and action.phase == action.Phase.MOVE:
				var partner = fixture.actors[1] if actor == fixture.actors[0] else fixture.actors[0]
				# Start the same finite, capsule/path-validated body correction that
				# a passing ally requests. The AI still owns its original assignment,
				# route, support, timeout and all subsequent actual motion.
				if actor.local_motion._start_side(partner, actor.global_position - partner.global_position, &"yield"):
					original = task.duplicate(true)
					mover = actor
					origin = actor.global_position
			elif actor == mover:
				var correcting: bool = actor.local_motion._point.is_finite() or actor.local_motion._hold_remaining > 0.0
				if correcting: correction_seconds += STEP
				displaced = maxf(displaced, actor.global_position.distance_to(origin))
				if task.get("plan_id", 0) != original.plan_id and not completed: canceled = true
				if task.get("plan_id", 0) == original.plan_id:
					fixed_deadline = fixed_deadline and task.expires_at == original.expires_at
					completed = completed or (task.get("complete", false) and ai.context._coordination_execution_completed and actor.global_position.distance_to(task.selected_position) <= 0.35)
		if completed or canceled: break
	check(not original.is_empty() and correction_seconds > 1.5 and displaced > 0.5, "A real released flank performs a finite side-step, yield and return longer than the ordinary stuck window")
	check(not canceled and fixed_deadline and completed, "The original flank survives local yielding and physically completes without replacing its plan or extending its deadline")
	print("YIELD_SAMPLE ", JSON.stringify({"seconds": correction_seconds, "displacement": displaced, "canceled": canceled, "completed": completed}))
	await _dispose(fixture)
	print("COOPERATION YIELD: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
