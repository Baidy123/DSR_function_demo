extends "res://tests/enemy/enemy_team_board_test.gd"

## Real registered bodies and leases. --reference runs the individual-query
## protocol for differential measurements against an unmodified project copy.
var observations: Array = []
var reference := false

func _run() -> void:
	reference = OS.get_cmdline_user_args().has("--reference")
	await _setup()
	for context in contexts: _versions(context)
	_batch_contract()
	_same_frame_changes()
	_live_footprints_and_fire()
	_choice_contract()
	if OS.get_cmdline_user_args().has("--benchmark"): _benchmark()
	print("RESERVATION_OBSERVATIONS ", JSON.stringify(observations))
	print("RESERVATION BATCH: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	quit(1 if failures else 0)

func _individual(offers: Array[Dictionary]) -> Array[bool]:
	var result: Array[bool] = []
	for offer in offers: result.append(board.reservation_offer_available(contexts[0], offer))
	return result

func _batch(offers: Array[Dictionary]) -> Array[bool]:
	return _individual(offers) if reference else board.reservation_offers_available(contexts[0], offers)

func _compare(offers: Array[Dictionary], label: String) -> Array[bool]:
	var input := offers.duplicate(true)
	var before: int = board.revision
	var leases: Dictionary = board._reservations.duplicate(true)
	var expected := _individual(offers)
	var actual := _batch(offers)
	check(actual == expected and offers == input and board.revision == before and board._reservations == leases, label)
	observations.append([label, actual])
	return actual

func _grid() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for x in range(-4, 5):
		for z in range(-3, 4): offers.append(_offer(contexts[0], _point(x, z), "grid:%d:%d" % [x, z]))
	return offers

func _batch_contract() -> void:
	check(_batch([]).is_empty(), "An empty batch has no results or side effects")
	var single: Array[Dictionary] = [_offer(contexts[0], _point(0))]
	check(_batch(single) == _individual(single), "A single offer retains the direct live-query fast path")
	var offers := _grid()
	var token: Dictionary = board.prepare_reservation(contexts[1], _offer(contexts[1], _point(0), "reserved"))
	check(not token.is_empty() and board.commit_reservation(contexts[1], token), "The fixture owns an accepted real reservation")
	offers.append(_offer(contexts[0], _point(0), "different-key"))
	var result := _compare(offers, "All grid positions preserve individual occupancy results and input isolation")
	check(not result[-1] and result.has(true), "The batch rejects an occupied destination while retaining legal alternatives")
	var valid: Dictionary = _offer(contexts[0], _point(-3, 2))
	var mixed: Array[Dictionary] = [valid, {}, valid.duplicate(true)]
	for change: Dictionary in [{"position": Vector3.INF}, {"scope": &"tactical"}, {"generation": -1},
		{"owner_action": &"missing_action"}, {"valid_until": 0.0}, {"captured_at": INF},
		{"relation_revision": -1}, {"team_config_revision": -1}, {"path_summary": {"firing_lane": {}}}]:
		var invalid := valid.duplicate(true)
		invalid.merge(change, true)
		mixed.append(invalid)
	result = _compare(mixed, "Mixed valid, duplicate and malformed offers keep every original validation gate")
	check(result[0] and not result[1] and result[2] and result.slice(3).all(func(value): return not value), "Invalid offers cannot inherit a neighboring offer's permission")
	board.release_reservation(contexts[1], token)
	var lane := {"origin": _point(-3) + Vector3.UP, "endpoint": _point(3) + Vector3.UP}
	token = board.prepare_reservation(contexts[1], _offer(contexts[1], _point(-3), "shooter", {"firing_lane": lane, "corridor_key": "narrow", "exclusive_corridor": true}))
	check(not token.is_empty(), "The fixture prepares a real corridor and firing-lane reservation")
	result = _compare([_offer(contexts[0], _point(0), "crossing"), _offer(contexts[0], _point(2, 3), "corridor", {"corridor_key": "narrow"}), _offer(contexts[0], _point(2, 3), "clear")], "Firing lanes and exclusive corridors remain independent constraints")
	check(result == [false, false, true], "A shared corridor and an actual reserved lane reject only their conflicting alternatives")
	board.release_reservation(contexts[1], token)

func _pair_at(point: Vector3) -> Array[Dictionary]:
	return [_offer(contexts[0], point), _offer(contexts[0], _point(-3, 3), "second-position")]

func _same_frame_changes() -> void:
	var frame := Engine.get_physics_frames()
	var original: Vector3 = actors[1].global_position
	var offers := _pair_at(_point(0))
	check(_batch(offers)[0], "The unoccupied point is initially available")
	actors[1].global_position = _point(0)
	check(not _compare(offers, "A second query in the same frame observes the moved friendly body")[0], "The moved body blocks the original point")
	actors[1].communication_group = &"other_radio"
	_versions(contexts[1])
	offers = _pair_at(_point(0))
	check(not _compare(offers, "Cross-radio physical safety is preserved")[0], "A radio change does not remove the friendly body")
	actors[1].is_dead = true
	check(_compare(offers, "Same-frame death removes obsolete body occupancy")[0], "Dead members do not retain a physical reservation claim")
	actors[1].is_dead = false
	actors[1].communication_group = &""
	_versions(contexts[1])
	actors[1].global_position = original
	offers = _pair_at(_point(0))
	var permission: Variant = contexts[0].permitted[&"engage"]
	contexts[0].permitted.erase(&"engage")
	check(not _compare(offers, "Same-frame permission removal invalidates the next batch")[0], "Unavailable actions cannot reserve a destination")
	contexts[0].permitted[&"engage"] = permission
	var token: Dictionary = board.prepare_reservation(contexts[1], _offer(contexts[1], _point(0)))
	check(not _compare(offers, "Same-frame preparation enters the next batch immediately")[0], "A newly pending destination cannot be double-booked")
	board.rollback_reservation(contexts[1], token)
	check(_compare(offers, "Same-frame rollback releases occupancy immediately")[0], "No cached pending reservation survives rollback")
	check(_batch(offers)[0], "A legal preview can be selected before another body moves")
	actors[1].global_position = _point(0)
	check(board.prepare_reservation(contexts[0], offers[0]).is_empty(), "Preparation rechecks a body that moved after preview")
	actors[1].global_position = original
	token = board.prepare_reservation(contexts[0], offers[0])
	actors[1].global_position = _point(0)
	check(not token.is_empty() and not board.commit_reservation(contexts[0], token), "Commit rechecks a body that moved after preparation")
	board.rollback_reservation(contexts[0], token)
	actors[1].global_position = original
	check(Engine.get_physics_frames() == frame, "Freshness checks require no extra physics frame")

func _choice_contract() -> void:
	var context = contexts[0]
	var blocked: Dictionary = {"id": &"engage", "destination": {"position": actors[1].global_position}, "cost": -99.0}
	var clear: Dictionary = {"id": &"engage", "destination": {"position": _point(-2, 2)}, "cost": 3.0, "plan": &"first"}
	var repeated := clear.duplicate(true)
	repeated.plan = &"second"
	repeated.cost = 2.0
	var stationary: Dictionary = {"id": &"engage", "destination": {}, "cost": 4.0}
	var options: Array[Dictionary] = [blocked, clear, repeated, stationary]
	var choices: Array[Dictionary] = context._basic_coordination_choices(options)
	check(choices.size() == 3 and choices[0].plan == &"first" and choices[1].plan == &"second" and choices[2].destination.is_empty(), "Filtering preserves candidate order, repeated positions and stationary defense")
	check(choices.size() == 3 and choices[0].cost == 3.0 and choices[1].cost == 2.0 and not clear.has("coordination_offer") and not choices[2].has("coordination_offer"), "Batching changes neither Utility scores nor input ownership")

func _live_footprints_and_fire() -> void:
	var frame := Engine.get_physics_frames()
	var other = actors[1]
	var original: Vector3 = other.global_position
	other.global_position = _point(0)
	var collision: CollisionShape3D = other.get_node("CollisionShape3D")
	var shape: Shape3D = collision.shape
	collision.shape = shape.duplicate()
	var offers := _pair_at(_point(1.3))
	check(_batch(offers)[0], "The original capsule leaves the neighboring destination free")
	collision.shape.radius = 0.8
	check(not _compare(offers, "A same-frame shape change refreshes the physical footprint")[0], "The enlarged capsule blocks the previous free neighbor")
	collision.shape = shape
	other.global_position = _point(-3)
	var endpoint := _point(3) + Vector3.UP
	board.publish_status(contexts[1], {"target_id": contexts[1].cooperation_target_id(), "position": other.global_position,
		"ready": true, "support_seconds": 2.0, "aim_position": endpoint})
	offers = _pair_at(_point(0))
	check(not _compare(offers, "A current finite friendly fire window excludes its lane")[0], "The live firing segment blocks a body destination")
	var rounds: int = other.ammo.magazine_rounds
	other.ammo.magazine_rounds = 0
	check(_compare(offers, "Same-frame ammo depletion revokes the published firing window")[0], "Empty magazines provide no stale physical fire lane")
	other.ammo.magazine_rounds = rounds
	check(not _batch(offers)[0], "Restoring actual ammo restores the still-fresh published window")
	board.elapsed += 0.36
	for context in contexts: context.evidence_elapsed_seconds += 0.36
	offers = _pair_at(_point(0))
	check(_compare(offers, "An aged fire window is no longer physical occupancy")[0], "Fire freshness retains the original 0.35-second boundary")
	other.global_position = original
	check(Engine.get_physics_frames() == frame, "Footprint, ammo and expiry checks all occur in the same physics frame")

func _benchmark() -> void:
	var offers := _grid()
	for warmup in 20: _batch(offers)
	var timings: Array = []
	var accepted := 0
	for round_index in 5:
		var started := Time.get_ticks_usec()
		for repeat in 100:
			for allowed in _batch(offers): accepted += int(allowed)
		timings.append((Time.get_ticks_usec() - started) / 1000.0)
	print("RESERVATION_BENCHMARK ", JSON.stringify({"ms": timings, "accepted": accepted, "offers": offers.size(), "batches": 100, "rounds": 5}))
