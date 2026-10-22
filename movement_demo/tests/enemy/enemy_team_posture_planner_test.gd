extends "res://tests/enemy/enemy_team_planner_test.gd"

func _run() -> void:
	var snapshot := _deployment(&"concentrate")
	var result: Dictionary = planner.propose(snapshot)
	check(result.tactic == &"concentrate" and result.posture == &"concentrate" and result.assignments.size() == 2, "Strong planner chooses reachable distinct support positions")
	check(result.decision.member_count == 3 and is_equal_approx(result.decision.baseline_cost, 30.0) and is_equal_approx(result.decision.proposed_cost, 12.0), "Team comparison includes the same unassigned third member")
	snapshot = _deployment(&"disperse")
	result = planner.propose(snapshot)
	check(result.tactic == &"disperse" and result.posture == &"disperse", "Complementary lateral offers choose dispersion")
	for member: Dictionary in snapshot.members: member.personal_baseline.cost = 0.1
	result = planner.propose(snapshot)
	check(result.assignments.size() == 2 and result.tactic == &"disperse", "Cheap personal scores cannot silently discard the only validated complementary team positions")
	snapshot = _deployment(&"concentrate")
	snapshot.members[0].personal_baseline.horizon = 8.0
	result = planner.propose(snapshot)
	check(is_equal_approx(result.decision.baseline_cost, 25.0) and is_equal_approx(result.decision.proposed_cost, 11.5), "Different personal horizons normalize to the same comparison window")
	snapshot = _deployment(&"concentrate")
	snapshot.members[0].actual_support.fire_ready = false
	snapshot.members[0].actual_support.measured_support_seconds = 0.0
	snapshot.members[0].offers[0].fire_ready = false
	snapshot.members[0].offers[0].measured_support_seconds = 0.0
	result = planner.propose(snapshot)
	check(result.assignments.size() == 2 and not result.assignments[0].reserved_offers[0].fire_ready, "A validated future firing position may be planned without inventing current fire readiness")
	snapshot.members[0].status.rounds = 0
	check(planner.propose(snapshot).assignments.is_empty(), "An empty support magazine cannot promise future covering fire")
	snapshot = _deployment(&"concentrate")
	snapshot.members[1].offers[0].position = snapshot.members[0].offers[0].position
	check(planner.propose(snapshot).assignments.is_empty(), "Concentration still rejects overlapping physical positions")
	snapshot = _deployment(&"concentrate")
	snapshot.members[2].personal_baseline.valid_until = 0.5
	result = planner.propose(snapshot)
	check(result.assignments.size() == 2 and not result.decision.baseline_ready and not result.decision.has("baseline_cost"), "Missing personal alternatives neither block legal team posts nor fabricate a baseline comparison")
	snapshot = _deployment(&"concentrate")
	var frozen := snapshot.duplicate(true)
	result = planner.propose(snapshot)
	check(snapshot == frozen and result.counters.pair_trials <= 36 and result.counters.conflict_checks <= 2048, "All deployment strategies share the original bounded pure comparison")
	snapshot.current_plan = _plan(snapshot, result)
	for member: Dictionary in snapshot.members: member.offers.clear()
	check(planner.propose(snapshot).operation == &"keep", "An executing deployment remains continuous when previews disappear")
	print("TEAM POSTURE PLANNER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _deployment(posture: StringName) -> Dictionary:
	var front := _offer(1, &"front_support", Vector3(5, 0, 0), "front", 1.0)
	front.path_summary.expected_fire_seconds = 2.0
	var mover := _offer(2, &"team_position", Vector3(5, 0, 3), "position", 1.0)
	mover.path_summary.posture = posture
	var snapshot := _snapshot([_member(1, [front]), _member(2, [mover]), _member(3, [])])
	snapshot.cooperation_level = 2
	snapshot.team_config_revision = 3
	for member: Dictionary in snapshot.members:
		member.erase("advanced_enabled")
		member.personal_baseline = {"cost": 10.0, "horizon": 4.0, "captured_at": 0.0, "valid_until": 8.0}
		member.status = {"rounds": 6, "reloading": false, "pressure": 0.0, "health_ratio": 1.0}
		for offer: Dictionary in member.offers: offer.team_config_revision = 3
	return snapshot
