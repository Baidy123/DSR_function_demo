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
	_claim_pressure()
	_plan_pressure()
	print("COOPERATION QUERY: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	quit(1 if failures else 0)

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

func _claim_pressure() -> void:
	var caller = contexts[0]
	var token: Dictionary = board.claim(contexts[1], {"kind": &"advance", "owner_action": &"cooperate", "duration": 2.0})
	check(not token.is_empty() and is_equal_approx(caller.cooperation_support_pressure(), 0.5) and is_equal_approx(caller.cooperation_support_pressure(), _snapshot_pressure(caller)), "A live advance claim contributes its remaining stationary-support demand")
	board.release(contexts[1], token)
	check(caller.cooperation_support_pressure() == 0.0, "Releasing a claim removes its demand in the same frame")
	board.claim(contexts[1], {"kind": &"advance", "owner_action": &"cooperate", "duration": 0.1})
	_advance(0.11)
	check(caller.cooperation_support_pressure() == 0.0 and _snapshot_pressure(caller) == 0.0, "An expired claim cannot leave support pressure behind")
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
