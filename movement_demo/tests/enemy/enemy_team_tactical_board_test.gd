extends "res://tests/enemy/enemy_team_board_test.gd"

## Isolated bridge contracts. Actors/Context are real; observations and locally
## validated offers are supplied at the board boundary. This is not autonomous
## search/flank acceptance, which belongs to the later action integration.
var source_serial := 1000

func _run() -> void:
	await _setup()
	_tactical_setup()
	if OS.get_cmdline_user_args().has("--timeout-only"):
		_stage_timeout_backoff()
		print("TEAM STAGE TIMEOUT: %d/%d passed" % [checks - failures, checks])
		scene.queue_free()
		await scene.tree_exited
		quit(1 if failures else 0)
		return
	_source_contract()
	_source_fallback_contract()
	_snapshot_isolation()
	_inspect_transaction()
	_visibility_and_permissions()
	_flank_facts()
	_lifecycle_and_repair()
	_geometry_contract()
	_segment_transaction()
	_stage_timeout_backoff()
	print("TEAM TACTICAL BOARD: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	quit(1 if failures else 0)

func _tactical_setup() -> void:
	for index in actors.size():
		var ai = actors[index].get_node("AI")
		Fixture.set_training_action(ai, &"cooperate", true)
		ai.set_physics_process(false)
		actors[index].set_physics_process(false)
		contexts[index] = ai.context
	_reset_tactical()

func _reset_tactical() -> void:
	board.reset()
	var points := [Vector3(-4, 0, -4), Vector3(4, 0, -4), Vector3(0, 0, -6)]
	for index in contexts.size():
		actors[index].global_position = arena.to_global(points[index])
		actors[index].communication_group = &"tactical_test"
		actors[index].is_dead = false
		actors[index].ammo.cancel_reload()
		var context = contexts[index]
		context.evidence_elapsed_seconds = 0.0
		context.sees_player = false
		context.is_alerted = true
		context.last_seen_position = _point(0, 0)
		board.register(context)
		_versions(context)

func _source(context, position: Vector3 = Vector3.INF, seconds: float = 20.0) -> Dictionary:
	source_serial += 1
	var point: Vector3 = _point(0, 0) if not position.is_finite() else position
	var old: bool = context.sees_player
	context.sees_player = true
	context.last_seen_position = point
	board.publish_coordination_source(context, {"source_id": source_serial, "source": &"visual", "target_id": context.cooperation_target_id(),
		"position": point, "captured_at": context.evidence_elapsed_seconds, "valid_until": context.evidence_elapsed_seconds + seconds})
	context.sees_player = old
	return board.coordination_source(context, context.cooperation_target_id())

func _tactical_offer(context, role: StringName, point: Vector3, key: String, source: Dictionary) -> Dictionary:
	var offer: Dictionary = board.coordination_identity(context)
	var summary := {"body_radius": 0.35, "tactical_key": "fixture_geometry", "blocked_position_sets": [], "sample_ids": [],
		"staging_position": point, "staging_seconds": 1.0, "observation_points": [source.position],
		"tactical_anchor": source.position, "tactical_axis": source.front_axis,
		"side": -1 if role == &"flank" else 1, "holds_front": role == &"front_support"}
	offer.merge({"scope": &"tactical", "role": role, "owner_action": &"search" if role in [&"inspect_left", &"inspect_right", &"search_sector"] else &"cooperate",
		"offer_key": key, "position_set_key": key, "position": point, "path_summary": summary,
		"target_id": source.target_id, "evidence_id": source.evidence_id, "captured_at": context.evidence_elapsed_seconds,
		"valid_until": context.evidence_elapsed_seconds + 0.8, "cost": 1.0, "travel_seconds": 4.0,
		"unavailable_seconds": 0.0, "exposed_seconds": 0.0, "information_loss": 0.0, "measured_support_seconds": 0.5,
		"movement_possible": true, "fire_ready": role == &"front_support"}, true)
	return offer

func _pair(source: Dictionary, remaining_segment: float = 0.0) -> void:
	var left := _tactical_offer(contexts[0], &"inspect_left", _point(-3), "left", source)
	var right := _tactical_offer(contexts[1], &"inspect_right", _point(3), "right", source)
	if remaining_segment > 0.0:
		left.accept_after = contexts[0].evidence_elapsed_seconds + remaining_segment
		right.accept_after = contexts[1].evidence_elapsed_seconds + remaining_segment
	check(board.submit_offers(contexts[0], [left]), "First locally validated inspection offer is published")
	check(board.submit_offers(contexts[1], [right]), "Complementary inspection offer is published")
	_advance(0.01)

func _accept(index: int) -> Dictionary:
	var context = contexts[index]
	var job: Dictionary = board.assignment(context)
	if job.is_empty(): return {}
	var pending: Dictionary = board.prepare_assignment(context, job, job.allowed_offer_keys[0])
	if pending.is_empty(): return {}
	board.clear_execution(actors[index].get_instance_id())
	if not board.commit_assignment(context, job, pending): return {}
	return board.assignment(context)

func _report(index: int, state: StringName, fields: Dictionary = {}) -> bool:
	var job: Dictionary = board.assignment(contexts[index])
	if job.is_empty(): return false
	job.merge({"state": state, "execution_valid": true, "segment_boundary": true}, true)
	job.merge(fields, true)
	return board.report_assignment(contexts[index], job)

func _source_contract() -> void:
	var a = contexts[0]
	var first := _source(a)
	check(not first.is_empty() and first.evidence_id > 0 and first.front_axis.length() > 0.99, "One legal source creates a shared frozen evidence identity and common horizontal axis")
	var original := first.duplicate(true)
	first.position = _point(8)
	check(board.coordination_source(contexts[1], a.cooperation_target_id()).position == original.position, "Shared source getter returns isolated values to team members")
	_advance(0.2)
	var second := _source(contexts[1])
	check(second.evidence_id == original.evidence_id and second.front_axis == original.front_axis, "New observer and timestamp at the same anchor do not rotate the planning frame")
	var revision_before: int = board.revision
	for index in 8: board.coordination_source(a, a.cooperation_target_id())
	check(board.revision == revision_before, "Reading shared sources creates no new revisions or leases")
	var changed := _source(a, _point(1))
	check(changed.evidence_id != original.evidence_id, "A real anchor change creates a different evidence identity")
	var count: int = board._coordination_sources.size()
	board.publish_coordination_source(a, {"source_id": 0, "source": &"noise", "target_id": 0, "position": _point(2), "captured_at": 0.0, "valid_until": 4.0})
	check(board._coordination_sources.size() == count, "Targetless noise without a real source identity is rejected")
	_reset_tactical()

func _source_fallback_contract() -> void:
	var a = contexts[0]
	var inspected: Dictionary = board.publish_inspection(a, {"target_id": a.cooperation_target_id(), "position": _point(0, 0),
		"source": &"visual_loss", "captured_at": 0.0, "valid_until": 20.0, "observer_position": actors[0].global_position})
	_advance(1.0)
	var sight := _source(a, _point(0, 0), 5.0)
	board.publish_coordination_source(a, {"source_id": int(inspected.id), "source": &"inspection", "target_id": a.cooperation_target_id(),
		"position": inspected.position, "captured_at": 0.0, "valid_until": 20.0})
	var latest: Dictionary = board.coordination_source(a, a.cooperation_target_id())
	check(latest.source == &"visual" and latest.captured_at == sight.captured_at, "The newer short sight remains current while an older valid investigation is retained")
	_advance(5.1)
	var fallback: Dictionary = board.coordination_source(a, a.cooperation_target_id())
	check(not fallback.is_empty() and fallback.source == &"inspection" and fallback.source_id == inspected.id and fallback.captured_at == 0.0 and fallback.valid_until == 20.0, "Expired five-second sight falls back to the acquired twenty-second clue without refreshing either original time")
	check(fallback.evidence_id == sight.evidence_id and fallback.front_axis == sight.front_axis and board.evidence(a, a.cooperation_target_id()).is_empty(), "Same-anchor fallback preserves the planning frame and creates no visual firing report")
	var revision_before: int = board.revision
	for index in 5:
		board.coordination_source(a, a.cooperation_target_id())
		board.publish_coordination_source(a, {"source_id": int(inspected.id), "source": &"inspection", "target_id": a.cooperation_target_id(),
			"position": inspected.position, "captured_at": 0.0, "valid_until": 20.0})
	check(board.revision == revision_before and board.coordination_source(a, a.cooperation_target_id()).valid_until == 20.0, "Repeated source publication and reads do not renew fallback evidence")
	_advance(14.0)
	check(board.coordination_source(a, a.cooperation_target_id()).is_empty(), "Investigation expires at its original deadline even after visual fallback")
	_reset_tactical()

func _snapshot_isolation() -> void:
	var source := _source(contexts[0])
	_pair(source)
	var job: Dictionary = _accept(0)
	check(not job.is_empty(), "Snapshot contract owns a real accepted assignment")
	if job.is_empty(): return
	var stored: Dictionary = board._coordination_plans[job.team_id].duplicate(true)
	var offers: Dictionary = board._coordination_offers.duplicate(true)
	check(not job.has("raw_offers") and not job.reserved_offers.is_empty(), "Public assignment exposes executable alternatives without internal previews")
	job.allowed_offer_keys.clear()
	job.partner_ids.clear()
	job.reserved_offers[0].path_summary.blocked_position_sets.append("caller_mutation")
	job.reserved_offers[0].position = _point(30)
	check(board._coordination_plans[stored.team_id] == stored, "Mutating nested public assignment values cannot alter the board's accepted plan")
	var snapshot_value: Dictionary = board._coordination_snapshot(stored.team_id, source, board._coordination_team_members(stored.team_id))
	check(board._coordination_plans[stored.team_id] == stored and board._coordination_offers == offers, "Projecting execution validity and current geometry does not modify the stored plan or previews")
	check(snapshot_value.current_plan.assignments.all(func(entry): return not entry.has("raw_offers")), "Planner snapshots omit internal previews for every assignment")
	snapshot_value.current_plan.assignments[0].reserved_offers[0].path_summary.blocked_position_sets.append("planner_mutation")
	snapshot_value.current_plan.required_participants.clear()
	snapshot_value.current_plan.tactical_frame.changed = true
	snapshot_value.members[0].offers[0].path_summary.observation_points.clear()
	check(board._coordination_plans[stored.team_id] == stored and board._coordination_offers == offers, "Nested planner snapshot edits cannot escape into either board registry")
	var unchanged: Dictionary = board.assignment(contexts[0])
	check(unchanged.assignment_id == job.assignment_id and unchanged.expires_at == job.expires_at and unchanged.allowed_offer_keys.size() > 0, "Snapshot reads preserve accepted identity, original deadline and legal choices")
	_reset_tactical()

func _inspect_transaction() -> void:
	var source := _source(contexts[0])
	_pair(source)
	var a: Dictionary = board.assignment(contexts[0])
	var b: Dictionary = board.assignment(contexts[1])
	check(not a.is_empty() and not b.is_empty() and a.role != b.role and a.plan_id == b.plan_id, "The planner assigns complementary ends under one shared plan")
	if a.is_empty() or b.is_empty(): return
	var before: int = board.revision
	var deadline: float = a.expires_at
	board.submit_offers(contexts[0], [])
	_advance(0.2)
	check(board.assignment(contexts[0]).assignment_id == a.assignment_id and board.assignment(contexts[0]).expires_at == deadline, "A missing preview batch neither revokes an offered slot nor extends its deadline")
	var accepted_a := _accept(0)
	var accepted_b := _accept(1)
	check(not accepted_a.is_empty() and not accepted_b.is_empty() and accepted_a.accepted and accepted_b.accepted, "Prepare, old execution clear and begin commit preserve each incoming reservation identity")
	if accepted_a.is_empty() or accepted_b.is_empty(): return
	_advance(0.01)
	a = board.assignment(contexts[0])
	check(a.phase == &"staging" and a.release_at < 0.0, "Accepting both actions does not pretend both actors have reached their entries")
	var stale := a.duplicate(true)
	stale.phase_id -= 1
	stale.state = &"arrived"
	check(not board.report_assignment(contexts[0], stale), "A previous phase cannot provide readiness for the current shared barrier")
	check(not _report(0, &"arrived"), "A remote actor cannot claim readiness without actually reaching its entry")
	actors[0].global_position = accepted_a.staging_position
	check(_report(0, &"arrived"), "The first real entry arrival is accepted")
	_advance(0.01)
	check(board.assignment(contexts[0]).release_at < 0.0, "The first actor waits for its required partner")
	actors[1].global_position = accepted_b.staging_position
	_advance(0.36)
	check(_report(1, &"arrived"), "The second real entry arrival is accepted")
	_advance(0.01)
	check(board.assignment(contexts[0]).release_at < 0.0, "A still-positioned partner with stale feedback cannot release the shared phase")
	check(_report(0, &"arrived"), "The first participant refreshes actual readiness in the same unchanged phase")
	_advance(0.01)
	a = board.assignment(contexts[0])
	b = board.assignment(contexts[1])
	check(a.phase == &"executing" and a.release_at == b.release_at and a.release_at >= 0.0, "One board release time starts the same phase for both participants")
	check(not _report(0, &"complete", {"checked_points": PackedVector3Array()}), "Arrival alone cannot complete inspection without actual ground observation")
	before = board.revision
	var snapshot: Dictionary = board.assignment(contexts[0])
	snapshot.reserved_offers[0].position = _point(8)
	check(board.assignment(contexts[0]).reserved_offers[0].position != _point(8) and board.revision == before, "Complete reserved alternatives are copied, not exposed for mutation")
	_source(contexts[0])
	check(board.assignment(contexts[0]).expires_at == deadline, "Fresh same-position sight does not refresh an accepted plan's fixed expiry")
	_advance(deadline + 0.1)
	check(board.assignment(contexts[0]).is_empty() and board.assignment(contexts[1]).is_empty(), "Uncompleted shared work expires without an infinite wait")
	_reset_tactical()

func _visibility_and_permissions() -> void:
	var source := _source(contexts[0])
	contexts[0].sees_player = true
	contexts[1].sees_player = true
	var false_inspection := _tactical_offer(contexts[0], &"inspect_left", _point(-3), "visible-left", source)
	check(not board.submit_offers(contexts[0], [false_inspection]), "Visible fighters are not eligible for hidden-target inspection")
	check(board.submit_offers(contexts[2], [_tactical_offer(contexts[2], &"inspect_right", _point(3), "blind-right", source)]), "The one blind member may still publish its legitimate investigation offer")
	_advance(0.01)
	check(board.assignment(contexts[2]).is_empty(), "Two visible fighters cannot create a fake second end and strand the one blind member in inspect_wait")
	contexts[0].sees_player = false
	contexts[1].sees_player = false
	_pair(source)
	check(board.assignment(contexts[2]).is_empty(), "An unassigned third blind member receives no waiting command and retains its personal choices")
	var ai = actors[0].get_node("AI")
	Fixture.set_training_action(ai, &"cooperate", false)
	ai.set_physics_process(false)
	check(board.assignment(contexts[0]).is_empty(), "Advanced OFF immediately loses its tactical role without changing basic occupancy authority")
	Fixture.set_training_action(ai, &"cooperate", true)
	ai.set_physics_process(false)
	_reset_tactical()

func _ready(index: int, enabled: bool) -> void:
	var context = contexts[index]
	board.publish_status(context, {"target_id": context.cooperation_target_id(), "position": actors[index].global_position,
		"ready": enabled, "support_seconds": 0.5 if enabled else 0.0, "aim_position": _point(0) + Vector3.UP,
		"firearms": true, "reloading": false, "rounds": actors[index].ammo.magazine_rounds, "moving": false})

func _flank_facts() -> void:
	var source := _source(contexts[0])
	var front := _tactical_offer(contexts[0], &"front_support", actors[0].global_position, "front", source)
	front.path_summary.staging_position = actors[0].global_position
	var far := _tactical_offer(contexts[1], &"flank", _point(3, 4), "far", source)
	far.path_summary.staging_position = actors[1].global_position
	_ready(0, false)
	check(board.submit_offers(contexts[0], [front]) and board.submit_offers(contexts[1], [far]), "Real local front and opposite-side route offers are admitted as values")
	_advance(0.01)
	check(board.assignment(contexts[1]).is_empty(), "Preview fire_ready cannot create a flank plan when the real front has no fire window")
	_ready(0, true)
	_advance(0.21)
	var moving: Dictionary = board.assignment(contexts[1])
	check(not moving.is_empty() and moving.role == &"flank", "A fresh real positive front window allows one finite opposite-side assignment")
	if not moving.is_empty():
		var copied := moving.duplicate(true)
		copied.assignment_revision += 1
		check(board.prepare_assignment(contexts[1], copied, copied.allowed_offer_keys[0]).is_empty(), "An altered assignment revision cannot prepare a body destination")
	var owner_count := 0
	for context in contexts:
		if board.assignment(context).get("role") == &"flank": owner_count += 1
	check(owner_count <= 1, "Three eligible members reserve at most floor(3/2) opposite-side roles")
	var accepted_front := _accept(0)
	var accepted_flank := _accept(1)
	check(not accepted_front.is_empty() and not accepted_flank.is_empty(), "Front and flank accept their actual production assignment transactions")
	if not accepted_front.is_empty() and not accepted_flank.is_empty():
		_advance(0.01)
		# Accepting clears the old execution's fire status. Publish the current
		# accepted front's measured readiness before requesting phase release.
		_ready(0, true)
		check(_report(0, &"arrived") and _report(1, &"arrived"), "Both accepted participants report their actual staging positions")
		_advance(0.01)
		var executing: Dictionary = board.assignment(contexts[1])
		check(not executing.is_empty() and executing.phase == &"executing", "Fresh real front fire and same-phase arrivals release the flank segment")
		if not executing.is_empty():
			check(not _report(1, &"complete"), "A moving flank cannot claim completion before reaching its assigned destination")
			actors[1].global_position = executing.selected_position
			check(_report(1, &"complete"), "Actual flank arrival completes through the report protocol")
			var front_execution: Dictionary = board.assignment(contexts[0])
			check(not front_execution.is_empty() and not front_execution.complete and board.elapsed < executing.expires_at, "Front support remains real and unfinished before the mover's completion is processed")
			_advance(0.01)
			check(board.assignment(contexts[0]).is_empty() and board.assignment(contexts[1]).is_empty() and board.reservation_snapshot(contexts[0]).is_empty(), "Completing the real maneuver releases front and flank leases without waiting for a fake front completion or expiry")
	_reset_tactical()

func _lifecycle_and_repair() -> void:
	var source := _source(contexts[0])
	_pair(source)
	var first := _accept(0)
	var second := _accept(1)
	check(not first.is_empty() and not second.is_empty(), "Repair fixture accepts both real assignment transactions")
	if first.is_empty() or second.is_empty(): return
	var left_id: int = first.assignment_id
	var left_deadline: float = first.expires_at
	_advance(0.01)
	check(board.submit_offers(contexts[2], [_tactical_offer(contexts[2], &"inspect_right", _point(3, 1), "replacement-right", source)]), "A spare qualified member supplies a replacement for only the failed slot")
	check(_report(1, &"unavailable"), "An actual failed participant reports its own finite assignment unavailable")
	_advance(0.01)
	var retained: Dictionary = board.assignment(contexts[0])
	var replacement: Dictionary = board.assignment(contexts[2])
	check(not retained.is_empty() and retained.assignment_id == left_id and retained.expires_at == left_deadline, "Repair preserves the unaffected assignment identity and original deadline")
	check(not replacement.is_empty() and retained.partner_ids.has(actors[2].get_instance_id()) and not retained.partner_ids.has(actors[1].get_instance_id()), "Replacing a member remaps protected partners without renewing their task")
	var generation_before: int = board.generation
	board.reset()
	check(board.generation > generation_before and board.assignment(contexts[0]).is_empty() and board.reservation_snapshot(contexts[0]).is_empty(), "Region reset clears plans, sources and both phases of occupancy")
	check(board.coordination_source(contexts[0], contexts[0].cooperation_target_id()).is_empty(), "Old source reads cannot resurrect a plan after reset")


func _geometry_contract() -> void:
	var planner = board._team_planner
	var first: Dictionary = board._reservation_footprint(contexts[0], _point(0))
	var second: Dictionary = board._reservation_footprint(contexts[1], _point(1.0))
	first.path_summary = {}
	second.path_summary = {}
	var cases: Array = []
	cases.append([first.duplicate(true), second.duplicate(true), true, "same-height spacing"])
	var upper := second.duplicate(true)
	upper.position.y = first.position.y + first.height
	cases.append([first.duplicate(true), upper, false, "non-overlapping floors"])
	var boundary_left := first.duplicate(true)
	boundary_left.radius = 0.25
	boundary_left.margin = 0.5
	var tangent := second.duplicate(true)
	tangent.radius = 0.25
	tangent.margin = 0.5
	tangent.position.x = first.position.x + 1.0
	cases.append([boundary_left, tangent, false, "exact binary-representable spacing boundary"])
	var wide := first.duplicate(true)
	wide.radius = 0.55
	wide.margin = 0.7
	var neighbour := second.duplicate(true)
	neighbour.position.x = first.position.x + 1.4
	cases.append([wide, neighbour, true, "different live body radius and margin"])
	var far := second.duplicate(true)
	far.position = _point(3)
	var shooter := first.duplicate(true)
	shooter.path_summary.firing_lane = {"origin": _point(0) + Vector3.UP, "endpoint": _point(2) + Vector3.UP}
	cases.append([shooter.duplicate(true), far, false, "body beyond a finite gunline endpoint"])
	var crossing := second.duplicate(true)
	crossing.position = _point(1.7)
	cases.append([shooter.duplicate(true), crossing, true, "body touching the finite gunline"])
	var above := crossing.duplicate(true)
	above.position.y += 3.0
	cases.append([shooter.duplicate(true), above, false, "gunline below an upper-floor capsule"])
	for value: Array in cases:
		var left: Dictionary = value[0]
		var right: Dictionary = value[1]
		var lhs := {"position": left.position, "path_summary": left.path_summary.duplicate(true)}
		var rhs := {"position": right.position, "path_summary": right.path_summary.duplicate(true)}
		for pair: Array in [[lhs, left], [rhs, right]]:
			pair[0].path_summary.merge({"body_radius": pair[1].radius, "body_height": pair[1].height, "spacing_margin": pair[1].margin}, true)
		var work := {"conflict_limit": 2048, "counters": {"conflict_checks": 0, "conflict_limit_reached": false}}
		var actual: bool = board._reservation_geometry_conflict(left, right)
		var proposed: bool = planner._conflict(work, lhs, rhs)
		check(actual == bool(value[2]) and proposed == actual and work.counters.conflict_checks == 1, "Planner and board share exact capsule/spacing rule: " + String(value[3]))
	var collider: CollisionShape3D = actors[0].get_node("CollisionShape3D")
	var original_shape: Shape3D = collider.shape
	collider.shape = original_shape.duplicate()
	collider.shape.radius = 0.5
	var training = actors[0].get_node("AI").training.profile
	var original_margin: float = contexts[0].setting(&"cooperation", &"spacing_margin", 0.45)
	training.set_setting(&"cooperation", &"spacing_margin", 0.6)
	var live_summary: Dictionary = board._coordination_physical_summary(contexts[0], {}, contexts[0].cooperation_target_id())
	var live_footprint: Dictionary = board._reservation_footprint(contexts[0], actors[0].global_position)
	check(live_summary.body_radius == live_footprint.radius and live_summary.body_height == live_footprint.height and live_summary.spacing_margin == live_footprint.margin and is_equal_approx(live_summary.body_radius, 0.5) and is_equal_approx(live_summary.spacing_margin, 0.6), "Planner input follows the actual changed collision shape and this actor's spacing setting")
	collider.shape = original_shape
	training.set_setting(&"cooperation", &"spacing_margin", original_margin)
	var exhausted := {"conflict_limit": 2048, "counters": {"conflict_checks": 2048, "conflict_limit_reached": false}}
	check(planner._conflict(exhausted, {"position": _point(-4)}, {"position": _point(4)}) and exhausted.counters.conflict_checks == 2048, "Optional full geometry remains inside the original shared conflict budget")


func _segment_transaction() -> void:
	_reset_tactical()
	var source := _source(contexts[0])
	var options: Array = []
	for index in 3:
		var offer := _tactical_offer(contexts[0], &"inspect_left", _point(-3, index), "left-%s" % index, source)
		offer.position_set_key = "left-slot"
		options.append(offer)
	check(board.submit_offers(contexts[0], options), "Three finite alternatives share one inspection role bundle")
	board.submit_offers(contexts[1], [_tactical_offer(contexts[1], &"inspect_right", _point(3), "right", source)])
	_advance(0.01)
	var original := _accept(0)
	check(not original.is_empty() and original.allowed_offer_keys.size() == 3, "Accepted assignment retains all three locally validated alternatives")
	if original.is_empty() or original.allowed_offer_keys.size() != 3: return
	check(board.prepare_assignment(contexts[0], original, "left-1").is_empty(), "An executing short segment cannot be switched before its reported boundary")
	check(_report(0, &"moving", {"segment_boundary": true}), "Local execution reports a legitimate short-segment boundary")
	var pending: Dictionary = board.prepare_assignment(contexts[0], board.assignment(contexts[0]), "left-1")
	check(not pending.is_empty() and pending.reservation_id != original.reservation_id and pending.expires_at == original.expires_at, "A new allowed position prepares a different physical token under the same fixed task deadline")
	if pending.is_empty(): return
	var owned: Array = board.reservation_snapshot(contexts[0]).filter(func(item): return item.actor_id == actors[0].get_instance_id())
	check(owned.size() == 2 and board.validate_reservation(contexts[0], board._reservations[original.reservation_id]), "Preparing an alternative keeps the previous accepted position until successful begin")
	var repeated: Dictionary = board.prepare_assignment(contexts[0], board.assignment(contexts[0]), "left-1")
	check(repeated.reservation_id == pending.reservation_id and repeated.accept_until == pending.accept_until, "Repeated preparation does not refresh the pending acceptance lease")
	board.rollback_assignment(contexts[0], board.assignment(contexts[0]), pending)
	var canceled_preparation: Dictionary = board.assignment(contexts[0])
	check(not canceled_preparation.is_empty() and canceled_preparation.reservation_id == original.reservation_id and canceled_preparation.expires_at == original.expires_at and board.validate_reservation(contexts[0], board._reservations[original.reservation_id]), "Canceling preparation before old execution clear preserves the real accepted lease")
	pending = board.prepare_assignment(contexts[0], canceled_preparation, "left-1")
	board.clear_execution(actors[0].get_instance_id())
	var during: Dictionary = board.assignment(contexts[0])
	check(not during.is_empty() and during.assignment_id == original.assignment_id, "Clearing the old body execution preserves the pending task transition identity")
	check(board.commit_assignment(contexts[0], during, pending), "Successful begin atomically commits the new allowed destination")
	var after: Dictionary = board.assignment(contexts[0])
	check(after.assignment_id == original.assignment_id and after.expires_at == original.expires_at and after.accepted_at == original.accepted_at and after.reservation_id == pending.reservation_id, "Destination transition preserves task identity, initial acceptance time and original deadline")
	var preparation_deadline: float = after.support_prepare_until
	check(board.commit_assignment(contexts[0], after, pending) and board.assignment(contexts[0]).support_prepare_until == preparation_deadline, "Idempotent commit does not renew even the finite support preparation window")
	_report(0, &"moving", {"segment_boundary": true})
	var last: Dictionary = board.prepare_assignment(contexts[0], board.assignment(contexts[0]), "left-2")
	var partner: Dictionary = board.assignment(contexts[1])
	check(not last.is_empty(), "A later legal boundary can prepare another retained alternative")
	if last.is_empty(): return
	board.clear_execution(actors[0].get_instance_id())
	board.rollback_assignment(contexts[0], board.assignment(contexts[0]), last)
	check(board.assignment(contexts[0]).is_empty() and board.assignment(contexts[1]).assignment_id == partner.assignment_id, "Begin failure ends only the failed task slot and never claims the canceled old execution resumed")
	check(board.reservation_snapshot(contexts[1]).all(func(item): return item.actor_id != actors[0].get_instance_id()), "Failed segment transition leaves no accepted or pending orphan occupancy")

func _stage_timeout_backoff() -> void:
	_reset_tactical()
	var source := _source(contexts[0])
	_pair(source, 1.6)
	var issued: Dictionary = board.assignment(contexts[0])
	_advance(1.1)
	var pending: Dictionary = board.assignment(contexts[0])
	check(not pending.is_empty() and pending.accept_until == issued.accept_until and pending.accept_until > board.elapsed and pending.accept_until <= pending.expires_at, "An already running personal segment gets one fixed bounded acceptance deadline beyond the ordinary one-second window")
	var refreshed := _tactical_offer(contexts[0], &"inspect_left", _point(-3), "left", source)
	refreshed.accept_after = contexts[0].evidence_elapsed_seconds + 4.0
	board.submit_offers(contexts[0], [refreshed])
	for index in 5: board.assignment(contexts[0])
	check(board.assignment(contexts[0]).accept_until == issued.accept_until and board.assignment(contexts[0]).expires_at == issued.expires_at, "Later previews and repeated reads cannot renew the issued acceptance or total task deadline")
	var left := _accept(0)
	var right := _accept(1)
	check(not left.is_empty() and not right.is_empty(), "Timeout fixture begins with two actual accepted board transactions")
	if left.is_empty() or right.is_empty(): return
	_advance(0.01)
	var staged: Dictionary = board.assignment(contexts[0])
	check(staged.phase == &"staging" and staged.release_at < 0.0, "A participant that has not reached its entry remains behind the real staging barrier")
	_advance(maxf(0.0, staged.stage_until - board.elapsed - 0.01))
	# New candidate previews remain valid while the body is late. A deadline
	# cannot be defeated by immediately recreating the same task from these values.
	board.submit_offers(contexts[0], [_tactical_offer(contexts[0], &"inspect_left", _point(-3), "left", source)])
	board.submit_offers(contexts[1], [_tactical_offer(contexts[1], &"inspect_right", _point(3), "right", source)])
	_advance(0.02)
	_advance(0.21)
	var after: Dictionary = board.assignment(contexts[0])
	check(after.is_empty(), "Stage timeout releases the failed wait and blocks immediate same-actor/same-position re-creation despite fresh offers")
	check(board.reservation_snapshot(contexts[0]).is_empty(), "Timed-out participants retain neither accepted nor newly recreated pending occupancy")
