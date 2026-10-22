extends "res://tests/enemy/enemy_team_posture_planner_test.gd"

func _run() -> void:
	if OS.get_cmdline_user_args().has("--support-extension"):
		_support_extension_case()
		print("SUPPORT EXTENSION: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	_support_extension_case()
	for count in [3, 4, 6]:
		var snapshot := _holding_team(count)
		var original := snapshot.duplicate(true)
		var result: Dictionary = planner.propose(snapshot)
		check(result.tactic == &"hold" and result.assignments.size() == count, "%d strong members each receive a real reserved holding post" % count)
		check(result.assignments.map(func(entry): return entry.actor_id).size() == count and result.assignments.all(func(entry): return entry.reserved_offers.size() > 0), "No unlocated following labels substitute for the remaining members")
		check(result.counters.pair_trials <= 36 and result.counters.conflict_checks <= 2048 and snapshot == original, "Full coverage preserves bounded pure planning")
		snapshot.current_plan = _plan(snapshot, result)
		for member: Dictionary in snapshot.members: member.offers.clear()
		check(planner.propose(snapshot).operation == &"keep", "Accepted holding posts survive disappearing preview offers")
	var snapshot := _holding_team(3)
	snapshot.members[2].offers[0].role = &"team_position"
	snapshot.members[2].offers[0].path_summary.posture = &"hold"
	snapshot.members[2].offers[0].path_summary.holds_position = true
	snapshot.members[2].offers[0].path_summary.expected_fire_seconds = 0.0
	snapshot.members[2].eligible_roles.append(&"team_position")
	var observation: Dictionary = planner.propose(snapshot)
	# The action validates personal sight before publishing an observation offer;
	# this pure planner case checks its reservation and lack of fire dependencies.
	check(observation.assignments.size() == 3 and observation.support_links.is_empty(), "A validated observation post participates without invented fire dependencies")
	snapshot = _holding_team(3)
	for member: Dictionary in snapshot.members: member.personal_baseline.clear()
	var result: Dictionary = planner.propose(snapshot)
	check(result.assignments.size() == 3 and not result.decision.baseline_ready, "Valid full-team posts do not wait on unrelated personal geometry")
	snapshot = _holding_team(3)
	snapshot.members[2].offers[0].position = snapshot.members[1].offers[0].position
	result = planner.propose(snapshot)
	check(result.assignments.size() == 2, "Full coverage never assigns overlapping concrete posts")
	snapshot = _holding_team(3)
	var late: Array = snapshot.members[2].offers.duplicate(true)
	snapshot.members[2].offers.clear()
	result = planner.propose(snapshot)
	snapshot.current_plan = _plan(snapshot, result)
	var frozen: Dictionary = snapshot.current_plan.duplicate(true)
	snapshot.members[2].offers = late
	result = planner.propose(snapshot)
	check(result.operation == &"extend" and result.assignments.size() == 1 and result.assignments[0].actor_id == 3 and snapshot.current_plan == frozen, "A late prepared member joins without replacing or renewing accepted teammates")
	snapshot.members[2].eligible_roles.append(&"team_position")
	snapshot.members[2].offers[0].role = &"team_position"
	snapshot.members[2].offers[0].travel_seconds = 0.5
	snapshot.members[2].offers[0].path_summary.posture = &"concentrate"
	snapshot.members[2].offers[0].path_summary.staging_seconds = 0.5
	result = planner.propose(snapshot)
	check(result.operation == &"extend" and result.support_links.any(func(link): return link.beneficiary_id == 3 and link.provider_id != 3 and link.requires_ready), "A late moving post receives a real support dependency without renewing existing assignments")
	print("TEAM CONTINUITY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _support_extension_case() -> void:
	var snapshot := _snapshot([_member(1, [_offer(1, &"front_support", Vector3(4, 0, 0), "provider")]), _member(2, [], false)])
	snapshot.requests = [_request(2)]
	var initial: Dictionary = planner.propose(snapshot)
	check(initial.tactic == &"support", "Actual reload request establishes the support plan used by the crash reproduction")
	snapshot.cooperation_level = 2
	snapshot.team_config_revision = 3
	snapshot.current_plan = _plan(snapshot, initial)
	snapshot.current_plan.support_links = [{"provider_id": 1, "beneficiary_id": 2, "kind": &"support", "request_id": 51, "requires_ready": false}]
	for member: Dictionary in snapshot.members:
		member.status = {"rounds": 12, "reloading": member.actor_id == 2}
		for offer: Dictionary in member.offers: offer.team_config_revision = 3
	var original := snapshot.duplicate(true)
	var kept: Dictionary = planner.propose(snapshot)
	check(kept.operation == &"keep" and snapshot == original, "Established support survives another planning tick without rebuilding its request or throwing")
	var move := _offer(3, &"team_position", Vector3(4, 0, 5), "joining")
	move.team_config_revision = 3
	move.path_summary.posture = &"concentrate"
	snapshot.members.append(_member(3, [move]))
	original = snapshot.duplicate(true)
	var extended: Dictionary = planner.propose(snapshot)
	check(extended.operation == &"extend" and extended.changed_actor_ids == [3], "A late combat member joins the ongoing support plan without replacing the original provider")
	check(extended.get("support_links", []).size() == 1 and extended.support_links[0].provider_id == 1 and extended.support_links[0].beneficiary_id == 3 and extended.support_links[0].kind == &"advance", "Extension adds the new mover's support dependency, not another copy of the old reload request")
	check(snapshot == original and snapshot.current_plan.support_links[0].beneficiary_id == 2 and snapshot.current_plan.request_id == 51, "The original beneficiary, request, execution and deadline remain unchanged")
	snapshot.requests.clear()
	check(planner.propose(snapshot).reason == &"support_request_ended", "A finished request still ends the original support plan")

func _holding_team(count: int) -> Dictionary:
	var snapshot := _deployment(&"concentrate")
	snapshot.members.clear()
	for id in range(1, count + 1):
		var offer := _offer(id, &"front_support", Vector3(5, 0, (id - 1) * 3.0), "hold%s" % id, 1.0)
		offer.travel_seconds = 0.0
		offer.path_summary.staging_seconds = 0.0
		offer.path_summary.expected_fire_seconds = 2.0
		offer.team_config_revision = 3
		var member := _member(id, [offer])
		member.personal_baseline = {"cost": 0.1, "horizon": 4.0, "captured_at": 0.0, "valid_until": 8.0}
		member.status = {"rounds": 6, "reloading": false, "pressure": 0.0, "health_ratio": 1.0}
		snapshot.members.append(member)
	return snapshot
