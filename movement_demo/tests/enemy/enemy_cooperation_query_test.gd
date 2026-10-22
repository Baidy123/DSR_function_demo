extends "res://tests/enemy/enemy_team_tactical_board_test.gd"

func _run() -> void:
	await _setup()
	_tactical_setup()
	var caller = contexts[0]
	var target: int = caller.cooperation_target_id()
	_publish_need(2.0)
	board.publish_status(contexts[2], {"position": actors[2].global_position, "target_id": target, "ready": true, "support_seconds": 1.0})
	var frame := Engine.get_physics_frames()
	caller.begin_geometry_evaluation()
	var initial: float = caller.cooperation_support_pressure()
	caller.begin_geometry_evaluation()
	check(is_equal_approx(initial, 0.25) and is_equal_approx(caller.cooperation_support_pressure(), initial), "Nested read-only batches preserve the real uncovered support interval")
	caller.end_geometry_evaluation()
	check(is_equal_approx(caller.cooperation_support_pressure(), initial), "Ending a nested batch preserves the outer read-only observation")
	caller.end_geometry_evaluation()
	actors[2].ammo.magazine_rounds = 0
	check(is_equal_approx(caller.cooperation_support_pressure(), 0.5), "Execution sees an empty supporting magazine immediately after a batch")
	actors[2].ammo.magazine_rounds = 5
	_publish_need(3.0, &"move")
	board.publish_status(contexts[2], {"position": actors[2].global_position, "target_id": target, "ready": true, "moving": true, "support_seconds": 1.0})
	check(is_equal_approx(caller.cooperation_support_pressure(), 0.75), "Moving fire cannot satisfy a stationary movement-support request")
	actors[1].communication_group = &"other_radio"
	check(caller.cooperation_support_pressure() == 0.0, "A same-frame radio change immediately removes the demand without re-registration")
	actors[1].communication_group = &"tactical_test"
	actors[1].is_dead = true
	check(caller.cooperation_support_pressure() == 0.0, "A same-frame death immediately removes the demand")
	actors[1].is_dead = false
	caller.begin_geometry_evaluation()
	check(is_equal_approx(caller.cooperation_support_pressure(), 0.75), "The next batch samples restored live demand rather than a previous cached zero")
	caller.end_geometry_evaluation()
	check(Engine.get_physics_frames() == frame, "All permission and magazine changes were checked within one physics frame")
	var rng := RandomNumberGenerator.new()
	rng.seed = 14062026
	var exact := true
	for sample in 256:
		for index in [1, 2]:
			var actor = actors[index]
			actor.is_dead = rng.randi_range(0, 7) == 0
			actor.communication_group = &"other_radio" if rng.randi_range(0, 5) == 0 else &"tactical_test"
			actor.ammo.magazine_rounds = rng.randi_range(0, 5)
			actor.shooting_enabled = rng.randi_range(0, 5) != 0
			var status := {"position": actor.global_position, "target_id": target if rng.randi_range(0, 4) != 0 else 0,
				"ready": rng.randi_range(0, 1) == 1, "moving": rng.randi_range(0, 1) == 1,
				"support_seconds": rng.randf_range(0.0, 4.0), "reloading": rng.randi_range(0, 1) == 1,
				"reload_seconds": rng.randf_range(0.0, 5.0), "lane_id": &"other" if rng.randi_range(0, 4) == 0 else &"target"}
			if rng.randi_range(0, 1) == 1: status.support_request = {"kind": [&"move", &"retreat", &"flank"][rng.randi_range(0, 2)], "duration": rng.randf_range(0.0, 6.0)}
			board.publish_status(contexts[index], status)
			board._members[actor.get_instance_id()].status.updated_at -= [0.0, 0.1, 0.35, 0.351][rng.randi_range(0, 3)]
		var expected := _snapshot_pressure(caller)
		exact = exact and is_equal_approx(caller.cooperation_support_pressure(), expected)
		caller.begin_geometry_evaluation()
		exact = exact and is_equal_approx(caller.cooperation_support_pressure(), expected) and is_equal_approx(caller.cooperation_support_pressure(), expected)
		caller.end_geometry_evaluation()
	check(exact, "256 mixed fresh/stale, moving, dead, radio-isolated and empty-magazine cases match the original public-snapshot semantics inside and outside batches")
	for actor in actors:
		actor.shooting_enabled = true
		actor.ammo.magazine_rounds = 5
	_reset_tactical()
	_snapshot_scopes()
	_planning_source_scopes()
	_execution_pressure()
	_plan_pressure()
	await _single_role_equivalence()
	print("COOPERATION QUERY: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	quit(1 if failures else 0)

func _single_role_equivalence() -> void:
	_reset_tactical()
	var caller = contexts[0]
	var actor = actors[0]
	var ai = actor.get_node("AI")
	var squad
	var roles: Array[StringName] = [&"search_sector", &"inspect_left", &"inspect_right", &"inspect_follow", &"assisted_reload", &"assisted_retreat", &"front_support", &"flank", &"team_position", &"unknown"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 15102026
	for level in [-1, 0, 1, 2]:
		if level == 0:
			squad = Fixture.attach_squad(arena, actors, 0)
			await physics_frame
			arena.enemy_environment()
		if level >= 0: squad.profile.level = level
		for member in actors: member.get_node("AI").refresh_configuration(true)
		_reset_tactical()
		var coordinator = caller._coordinator()
		_source(caller)
		var permitted: Dictionary = caller.permitted.duplicate()
		var target: int = caller.cooperation_target_id()
		var frame := Engine.get_physics_frames()
		var exact := true
		var compared := 0
		var allowed := 0
		for sample in 256:
			caller.permitted = permitted.duplicate()
			for action in [&"cooperate", &"search", &"reload", &"covering_retreat"]:
				if sample > 0 and rng.randi_range(0, 3) == 0: caller.permitted.erase(action)
			caller.sees_player = (sample & 1) != 0
			caller.is_alerted = (sample & 2) == 0
			caller.noise_search_origin = _point(1, 1) if (sample & 4) != 0 else Vector3.INF
			actor.shooting_enabled = (sample & 8) == 0
			actor.melee_active = (sample & 16) != 0
			actor.is_dead = (sample & 32) != 0
			actor.communication_group = &"other_radio" if (sample & 64) != 0 else &"tactical_test"
			paused = (sample & 128) != 0
			for query_target in [0, target, target + 1]:
				var expected: Array = coordinator._coordination_roles(caller, query_target)
				for role in roles:
					var actual: bool = coordinator._coordination_role_allowed(caller, query_target, role)
					exact = exact and actual == expected.has(role)
					compared += 1
					if actual: allowed += 1
		paused = false
		actor.is_dead = false
		actor.melee_active = false
		actor.shooting_enabled = true
		actor.communication_group = &"tactical_test"
		caller.permitted = permitted
		caller.noise_search_origin = Vector3.INF
		check(exact and compared == 7680 and Engine.get_physics_frames() == frame, "Level %d: one-role checks match all 7680 full-enumeration results across same-frame permissions, target, vision, noise, body, death, radio and pause changes" % level)
		check(allowed > 0 if level != 0 else allowed == 0, "Level %d: equivalence covers legal posts as well as denials" % level)
	_reset_tactical()

func _publish_need(seconds: float, kind: StringName = &"reload") -> void:
	var status := {"position": actors[1].global_position, "target_id": contexts[0].cooperation_target_id()}
	if kind == &"reload":
		status.reloading = true
		status.reload_seconds = seconds
	else: status.support_request = {"kind": kind, "duration": seconds}
	board.publish_status(contexts[1], status)

func _snapshot_scopes() -> void:
	var caller = contexts[0]
	_publish_need(2.0)
	var before: Dictionary = board._members.duplicate(true)
	caller.begin_geometry_evaluation()
	var expected := _snapshot_pressure(caller)
	caller.begin_cooperation_preview()
	check(is_equal_approx(caller.cooperation_support_pressure(), expected), "Candidate preview and geometry batch agree with the full live snapshot")
	var other: Dictionary = caller.cooperation_snapshot(caller.cooperation_target_id() + 1)
	check(other.requests.is_empty() and other.supports.is_empty(), "A different target never reuses the current target's support requests")
	caller.end_cooperation_preview()
	caller.end_geometry_evaluation()
	check(board._members == before, "Full and reduced read-only projections do not mutate published member status")
	actors[1].communication_group = &"other_radio"
	check(caller.cooperation_snapshot().requests.is_empty(), "Execution drops stale batch membership immediately after a radio change")
	actors[1].communication_group = &"tactical_test"
	caller.begin_geometry_evaluation()
	check(not caller.cooperation_snapshot().requests.is_empty(), "A new same-frame batch sees restored live membership")
	caller.end_geometry_evaluation()
	_reset_tactical()

func _planning_source_scopes() -> void:
	var caller = contexts[0]
	var initial := _source(caller)
	var frame := Engine.get_physics_frames()
	caller.begin_cooperation_preview()
	var observed: Dictionary = caller.coordination_source(caller.cooperation_target_id())
	check(observed.evidence_id == initial.evidence_id and observed.position == initial.position, "Candidate preparation reads the real planning source")
	observed.position = Vector3.INF
	observed.evidence_id = -1
	caller.begin_cooperation_preview()
	var nested: Dictionary = caller.coordination_source(caller.cooperation_target_id())
	check(nested.evidence_id == initial.evidence_id and nested.position == initial.position, "Mutating a returned source cannot corrupt a nested candidate preparation")
	caller.end_cooperation_preview()
	check(caller.coordination_source(caller.cooperation_target_id() + 1).is_empty(), "Nested planning-source reuse remains isolated by target")
	caller.end_cooperation_preview()
	var replacement := _source(caller, initial.position + Vector3(2, 0, 0))
	check(caller.coordination_source(caller.cooperation_target_id()).evidence_id == replacement.evidence_id and replacement.evidence_id != initial.evidence_id, "Execution immediately sees replacement evidence after candidate preparation")
	caller.begin_cooperation_preview()
	check(caller.coordination_source(caller.cooperation_target_id()).evidence_id == replacement.evidence_id and Engine.get_physics_frames() == frame, "The next same-frame preparation reads the new source with its original identity")
	caller.end_cooperation_preview()
	_reset_tactical()

func _execution_pressure() -> void:
	var caller = contexts[0]
	_publish_need(2.0, &"advance")
	check(is_equal_approx(caller.cooperation_support_pressure(), 0.5) and is_equal_approx(caller.cooperation_support_pressure(), _snapshot_pressure(caller)), "Real movement execution contributes its finite stationary-support demand")
	board.clear_execution(actors[1].get_instance_id())
	check(caller.cooperation_support_pressure() == 0.0, "Ending execution removes its demand in the same frame")
	_publish_need(0.1, &"advance")
	_advance(0.36)
	check(caller.cooperation_support_pressure() == 0.0 and _snapshot_pressure(caller) == 0.0, "Expired actual execution cannot leave support pressure behind")
	_reset_tactical()

func _plan_pressure() -> void:
	var source := _source(contexts[0])
	_pair(source)
	var caller = contexts[2]
	check(caller.cooperation_support_pressure() == 0.0, "Unaccepted inspection offers do not manufacture preparation support")
	var assignment := _accept(0)
	var expected := _snapshot_pressure(caller)
	check(not assignment.is_empty() and expected > 0.0 and is_equal_approx(caller.cooperation_support_pressure(), expected), "A real accepted plan contributes its bounded preparation support window")
	actors[0].communication_group = &"other_radio"
	check(caller.cooperation_support_pressure() == 0.0 and _snapshot_pressure(caller) == 0.0, "Same-frame departure invalidates accepted preparation demand")
	actors[0].communication_group = &"tactical_test"
	var prepared_until: float = assignment.get("support_prepare_until", board.elapsed)
	_advance(maxf(0.0, prepared_until - board.elapsed) + 0.01)
	check(caller.cooperation_support_pressure() == 0.0 and _snapshot_pressure(caller) == 0.0, "An accepted but inactive assignment cannot renew its preparation window on query")

## The old observable full-snapshot calculation remains the differential oracle.
func _snapshot_pressure(context) -> float:
	var data: Dictionary = board.snapshot(context, context.cooperation_target_id())
	var id: int = context.actor.get_instance_id()
	var need := 0.0
	for request in data.requests:
		if request.beneficiary_id == id: continue
		var covered := 0.0
		for support in data.supports:
			if support.owner_id == id or support.get("lane_id", &"target") != &"target": continue
			if request.get("kind", &"") in [&"advance", &"flank", &"move"] and support.get("moving", false): continue
			covered = maxf(covered, float(support.support_seconds))
		need = maxf(need, maxf(0.0, float(request.get("remaining", 0.0)) - covered))
	return clampf(need / maxf(0.1, context.utility_horizon_seconds), 0.0, 1.0)
