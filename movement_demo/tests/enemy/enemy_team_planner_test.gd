extends SceneTree

const Planner = preload("res://scripts/enemy/services/enemy_team_planner.gd")
var planner := Planner.new()
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_basic_contract()
	_inspection_contract()
	_flank_contract()
	_support_contract()
	_search_contract()
	_continuity_contract()
	_input_and_budget_contract()
	print("TEAM PLANNER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + label)

func _offer(actor_id: int, role: StringName, point: Vector3, key: String, cost: float = 1.0, group: String = "") -> Dictionary:
	var summary := {"body_radius": 0.3, "tactical_key": "wall_round_1", "side": -1 if role == &"flank" else 1,
		"holds_front": role == &"front_support", "corridor_key": "", "exclusive_corridor": false,
		"blocked_position_sets": []}
	if role == &"search_sector":
		summary.merge({"grid_key": "grid", "search_round_id": 1, "sample_ids": [key]})
	return {"actor_id": actor_id, "member_generation": 1, "config_revision": 1,
		"environment_revision": 1, "navigation_revision": 1, "relation_revision": 1,
		"target_id": 7, "evidence_id": 9, "owner_action": &"search" if role in [&"inspect_left", &"inspect_right", &"search_sector"] else &"cooperate",
		"offer_key": key, "role": role, "scope": &"basic" if role == &"independent_position" else &"tactical",
		"position_set_key": group if not group.is_empty() else key, "position": point,
		"path_summary": summary, "travel_seconds": 1.0, "unavailable_seconds": 1.0,
		"exposed_seconds": 1.0, "information_loss": 0.0, "cost": cost,
		"fire_ready": role == &"front_support", "measured_support_seconds": 1.0 if role == &"front_support" else 0.0,
		"movement_possible": true, "captured_at": 0.0, "valid_until": 8.0}

func _member(actor_id: int, offers: Array, advanced: bool = true) -> Dictionary:
	var roles: Array = []
	for offer in offers:
		if not roles.has(offer.role): roles.append(offer.role)
	return {"actor_id": actor_id, "member_generation": 1, "config_revision": 1,
		"position": Vector3(actor_id * 3.0, 0, 12), "advanced_enabled": advanced,
		"eligible_roles": roles, "offers": offers, "on_far_side": false,
		"actual_support": {"fire_ready": roles.has(&"front_support"), "measured_support_seconds": 1.0,
			"captured_at": 0.0, "valid_until": 8.0}}

func _snapshot(members: Array) -> Dictionary:
	return {"now": 1.0, "generation": 1, "team_id": 1, "domain": "arena/team/target",
		"target_id": 7, "evidence_id": 9, "environment_revision": 1, "navigation_revision": 1,
		"relation_revision": 1, "members": members, "occupancy": [], "requests": [],
		"failures": [], "flank_owner_ids": [], "current_plan": {}}

func _occupancy(actor_id: int, point: Vector3, group: String) -> Dictionary:
	return {"actor_id": actor_id, "reservation_id": actor_id * 10, "kind": &"reservation",
		"position": point, "position_set_key": group, "path_summary": {"body_radius": 0.3},
		"captured_at": 0.0, "valid_until": 8.0}

func _request(actor_id: int, kind: StringName = &"reload", actual: bool = true) -> Dictionary:
	return {"actor_id": actor_id, "request_id": 51, "kind": kind, "actual": actual, "accepted": false,
		"target_id": 7, "evidence_id": 9, "captured_at": 0.0, "valid_until": 8.0}

func _pair() -> Dictionary:
	return _snapshot([
		_member(1, [_offer(1, &"inspect_left", Vector3(-4, 0, 0), "left_a", 1, "left"),
			_offer(1, &"inspect_left", Vector3(-4, 0, 2), "left_b", 2, "left")]),
		_member(2, [_offer(2, &"inspect_right", Vector3(4, 0, 0), "right_a", 1, "right")])])

func _plan(snapshot: Dictionary, proposal: Dictionary) -> Dictionary:
	var plan := {"tactic": proposal.tactic, "expires_at": 12.0, "execution_valid": true,
		"segment_boundary": false, "assignments": proposal.assignments.duplicate(true),
		"required_participants": proposal.required_participants.duplicate(), "plan_id": 81, "plan_version": 2}
	for key in [&"generation", &"team_id", &"domain", &"target_id", &"evidence_id"]: plan[key] = snapshot[key]
	if proposal.has("request_id"): plan.request_id = proposal.request_id
	for assignment in plan.assignments:
		assignment.execution_valid = true
		assignment.assignment_id = 100 + assignment.actor_id
		assignment.assignment_revision = 3
		assignment.expires_at = 12.0
		assignment.member_generation = 1
	return plan

func _basic_contract() -> void:
	var one := _snapshot([_member(1, [_offer(1, &"inspect_left", Vector3(-4, 0, 0), "l"), _offer(1, &"inspect_right", Vector3(4, 0, 0), "r")])])
	check(planner.propose(one).assignments.is_empty(), "Solo never pairs with itself or gains a tactical waiting role")
	var basic := _snapshot([
		_member(1, [_offer(1, &"independent_position", Vector3.ZERO, "b1", 1, "slot")], false),
		_member(2, [_offer(2, &"independent_position", Vector3.ZERO, "b2", 1, "slot"), _offer(2, &"independent_position", Vector3(3, 0, 0), "b3")], false)])
	for member in basic.members:
		for offer in member.offers:
			offer.target_id = 0
			offer.evidence_id = 0
	var result: Dictionary = planner.propose(basic)
	check(result.assignments.is_empty() and result.basic_choices.size() == 2, "Advanced OFF keeps basic position proposals without tactical assignments")
	check(result.basic_choices[1].allowed_offer_keys == ["b3"], "Basic positions reject another member's complete alternative set")
	basic.occupancy = [_occupancy(99, Vector3(3, 0, 0), "external_group")]
	check(planner.propose(basic).basic_choices.size() == 1, "Physical occupancy outside this tactical group still blocks a position")
	var pair := _pair()
	pair.members.append(_member(3, [_offer(3, &"independent_position", Vector3(-4, 0, 2), "overlap"), _offer(3, &"independent_position", Vector3(0, 0, 5), "free")], false))
	result = planner.propose(pair)
	check(result.assignments.size() == 2 and result.basic_choices.size() == 1 and result.basic_choices[0].allowed_offer_keys == ["free"], "A third basic member cannot choose any newly assigned tactical alternative before occupancy is committed")
	check(not result.basic_choices[0].has("assignment_id") and not result.basic_choices[0].has("reservation_id"), "Planner never manufactures basic execution or reservation identities")

func _inspection_contract() -> void:
	var snapshot := _pair()
	var result: Dictionary = planner.propose(snapshot)
	check(result.operation == &"replace" and result.tactic == &"inspect" and result.assignments.size() == 2, "Two compatible endpoints produce two different investigators")
	check(result.assignments[0].allowed_offer_keys.size() == 2 and result.assignments[1].allowed_offer_keys.size() == 1, "Each investigator retains its own same-end alternatives")
	snapshot.members[1].offers[0].position = Vector3(-4, 0, 2)
	check(planner.propose(snapshot).assignments.is_empty(), "A conflict with even a non-best alternative rejects the combined position sets")
	snapshot = _pair()
	snapshot.members[1].offers[0].path_summary.tactical_key = "different_cover"
	check(planner.propose(snapshot).assignments.is_empty(), "Left and right from different frozen cover geometry cannot become a pair")
	snapshot = _pair()
	for member in snapshot.members:
		for offer in member.offers:
			offer.path_summary.corridor_key = "one_narrow_entrance"
			offer.path_summary.exclusive_corridor = true
	check(planner.propose(snapshot).assignments.is_empty(), "Different endpoint positions cannot promise simultaneous use of the same exclusive corridor")
	snapshot = _pair()
	snapshot.members[1].offers[0].movement_possible = false
	check(planner.propose(snapshot).assignments.is_empty(), "An immobile endpoint offer cannot promise investigation")
	snapshot = _pair()
	snapshot.members[1].advanced_enabled = false
	check(planner.propose(snapshot).assignments.is_empty(), "One ON and one OFF member cannot create a tactical two-end barrier")
	# The actual live-idle failure: two visible fighters are not search-eligible.
	snapshot = _pair()
	snapshot.members[0].eligible_roles = [&"front_support"]
	snapshot.members[1].eligible_roles = [&"front_support"]
	snapshot.members.append(_member(3, [_offer(3, &"inspect_left", Vector3(-4, 0, 0), "l3"), _offer(3, &"inspect_right", Vector3(4, 0, 0), "r3"), _offer(3, &"independent_position", Vector3(0, 0, 6), "b3")]))
	result = planner.propose(snapshot)
	check(result.assignments.is_empty() and result.basic_choices.size() == 1, "Visible fighters' stale inspect offers do not strand one blind member in an unassigned team wait")
	snapshot = _pair()
	snapshot.members.append(_member(3, [_offer(3, &"inspect_left", Vector3(-4, 0, 0), "l3", 3), _offer(3, &"inspect_right", Vector3(4, 0, 0), "r3", 3), _offer(3, &"independent_position", Vector3(0, 0, 6), "b3")]))
	result = planner.propose(snapshot)
	check(result.assignments.size() == 2 and result.basic_choices.size() == 1 and result.basic_choices[0].actor_id == 3, "Three blind members assign only two endpoints; the unassigned third keeps basic and personal choices")

func _flank_contract() -> void:
	for count in [2, 3, 6]:
		var members: Array = [_member(1, [_offer(1, &"front_support", Vector3(4, 0, 0), "front")])]
		for actor_id in range(2, count + 1): members.append(_member(actor_id, [_offer(actor_id, &"flank", Vector3(-4, 0, actor_id * 2), "flank%d" % actor_id)]))
		var snapshot := _snapshot(members)
		var result: Dictionary = planner.propose(snapshot)
		var flanks: Array = result.assignments.filter(func(a): return a.role == &"flank")
		check(result.tactic == &"flank" and flanks.size() == floori(float(count) / 2.0), "%d eligible members preserve a real front and assign at most half to flank" % count)
	var snapshot := _snapshot([_member(1, [_offer(1, &"front_support", Vector3(4, 0, 0), "front")]), _member(2, [_offer(2, &"flank", Vector3(-4, 0, 0), "flank")])])
	snapshot.members[1].on_far_side = true
	snapshot.flank_owner_ids = [2, 2]
	check(planner.propose(snapshot).tactic == &"flank", "Actual body, pending and committed flank ownership count one actor once")
	snapshot.flank_owner_ids = []
	snapshot.members[1].on_far_side = false
	var off := _member(3, [], false)
	off.on_far_side = true
	snapshot.members.append(off)
	check(planner.propose(snapshot).assignments.is_empty(), "An OFF member does not enlarge quota but its actual far-side body still consumes the side constraint")
	snapshot.members.pop_back()
	snapshot.members[0].actual_support.measured_support_seconds = 0.0
	check(planner.propose(snapshot).assignments.is_empty(), "A front label and fire_ready flag without actual support time cannot promise a flank release")

func _support_contract() -> void:
	var snapshot := _snapshot([_member(1, [_offer(1, &"front_support", Vector3(4, 0, 0), "front")]), _member(2, [], false)])
	snapshot.requests = [_request(2)]
	var result: Dictionary = planner.propose(snapshot)
	check(result.tactic == &"support" and result.assignments.size() == 1 and result.assignments[0].beneficiary_id == 2, "An advanced provider may cover an OFF member's actual reload without commanding that member")
	check(result.required_participants.is_empty() and result.assignments[0].actor_id == 1, "An OFF beneficiary is not assigned or required to join a tactical barrier")
	snapshot.requests[0].actual = false
	check(planner.propose(snapshot).assignments.is_empty(), "An unstarted reload proposal does not create a support plan")
	snapshot.requests = [_request(2, &"advance", false)]
	check(planner.propose(snapshot).assignments.is_empty(), "An unaccepted advance offer is not a real preparation request")
	snapshot.requests[0].accepted = true
	check(planner.propose(snapshot).tactic == &"support", "An accepted finite advance request can obtain a real provider")
	snapshot.members[0].offers[0].request_id = 777
	check(planner.propose(snapshot).assignments.is_empty(), "A request-specific front offer cannot cover a different request")
	snapshot.members[0].offers[0].erase("request_id")
	snapshot.requests = [_request(2)]
	result = planner.propose(snapshot)
	snapshot.current_plan = _plan(snapshot, result)
	snapshot.current_plan.execution_valid = false
	snapshot.current_plan.assignments[0].execution_valid = false
	snapshot.requests.clear()
	check(planner.propose(snapshot).reason == &"support_request_ended", "Repair cannot resurrect support after the beneficiary's real request ended")

func _search_contract() -> void:
	var members: Array = []
	for actor_id in [1, 2]:
		var a := _offer(actor_id, &"search_sector", Vector3(-4, 0, 0), "a%d" % actor_id, 1, "sector_a")
		var b := _offer(actor_id, &"search_sector", Vector3(4, 0, 0), "b%d" % actor_id, 2, "sector_b")
		a.path_summary.sample_ids = ["A"]
		b.path_summary.sample_ids = ["B"]
		members.append(_member(actor_id, [a, b]))
	var snapshot := _snapshot(members)
	var result: Dictionary = planner.propose(snapshot)
	check(result.tactic == &"search" and result.assignments.size() == 2, "Both actors' cheap A and dearer B bundles remain available so legal A+B is discovered")
	check(result.assignments[0].reserved_position_sets != result.assignments[1].reserved_position_sets, "Search assignments use complementary sample and position sets")
	for member in snapshot.members:
		for offer in member.offers: offer.path_summary.sample_ids = ["same"]
	check(planner.propose(snapshot).assignments.size() == 1, "A single remaining search sector is assigned serially instead of duplicating samples")
	snapshot.target_id = 0
	for member in snapshot.members:
		for offer in member.offers: offer.target_id = 0
	check(planner.propose(snapshot).tactic == &"search", "Unknown-source search may use target zero with a real frozen evidence identity")
	snapshot.evidence_id = 0
	for member in snapshot.members:
		for offer in member.offers: offer.evidence_id = 0
	check(planner.propose(snapshot).assignments.is_empty(), "Unknown sources without an evidence identity cannot share a tactical search")

func _continuity_contract() -> void:
	var snapshot := _pair()
	var proposed: Dictionary = planner.propose(snapshot)
	snapshot.current_plan = _plan(snapshot, proposed)
	for member in snapshot.members: member.offers.clear()
	snapshot.now = 9.0
	var before: Dictionary = snapshot.duplicate(true)
	var result: Dictionary = planner.propose(snapshot)
	check(result.operation == &"keep" and result.assignments.is_empty() and result.changed_actor_ids.is_empty(), "An actual valid short segment survives absent and expired local candidate caches without a new identity")
	check(snapshot == before, "Keep does not refresh any task, offer or assignment deadline")
	snapshot = _pair()
	snapshot.current_plan = _plan(snapshot, planner.propose(snapshot))
	snapshot.current_plan.execution_valid = false
	snapshot.current_plan.assignments[1].execution_valid = false
	snapshot.members[1].offers = [_offer(2, &"inspect_right", Vector3(4, 0, 2), "right_new", 2, "right_new_set")]
	var protected: Dictionary = snapshot.current_plan.assignments[0].duplicate(true)
	result = planner.propose(snapshot)
	check(result.operation == &"repair" and result.assignments.size() == 1 and result.changed_actor_ids == [2], "Local repair changes only the failed member's same-role position")
	check(snapshot.current_plan.assignments[0] == protected and result.assignments[0].previous_actor_id == 2, "Unaffected assignment identity, revision and deadline remain exactly intact")
	snapshot.members[1].offers[0].position = Vector3(-4, 0, 2)
	check(planner.propose(snapshot).operation == &"none", "Repair checks every protected alternative even when global occupancy is empty")
	snapshot.current_plan.assignments[0].reserved_offers.pop_back()
	check(planner.propose(snapshot).reason == &"invalid_assignments", "An incomplete frozen allowed-offer projection is rejected instead of assumed complete")
	snapshot = _pair()
	snapshot.current_plan = _plan(snapshot, planner.propose(snapshot))
	snapshot.current_plan.execution_valid = false
	snapshot.current_plan.assignments[1].execution_valid = false
	snapshot.members[1].offers.clear()
	snapshot.members.append(_member(3, [_offer(3, &"inspect_right", Vector3(4, 0, 2), "substitute", 1, "right_new")]))
	result = planner.propose(snapshot)
	check(result.operation == &"repair" and result.assignments[0].previous_actor_id == 2 and result.assignments[0].actor_id == 3 and result.required_participants == [1, 3], "A replacement identifies the old slot and suggests a revised participant set without issuing phase IDs")
	snapshot.failures = [{"actor_id": 3, "position_set_key": "right_new", "valid_until": 20.0}]
	check(planner.propose(snapshot).operation == &"none", "Failed positions remain cooled down across fresh offers and plan attempts")

func _input_and_budget_contract() -> void:
	var snapshot := _pair()
	var original: Dictionary = snapshot.duplicate(true)
	var first: Dictionary = planner.propose(snapshot)
	check(snapshot == original, "A fresh proposal leaves the complete caller snapshot unchanged")
	snapshot.members.reverse()
	for member in snapshot.members: member.offers.reverse()
	check(planner.propose(snapshot) == first, "Equal costs and shuffled input keep stable deterministic assignment and counters")
	check(original.members[0].offers.size() == 2, "Planner does not modify caller-owned offer arrays")
	for field in [&"member_generation", &"config_revision", &"relation_revision", &"environment_revision", &"navigation_revision", &"target_id", &"evidence_id"]:
		var invalid := _pair()
		invalid.members[1].offers[0][field] = 999
		check(planner.propose(invalid).assignments.is_empty(), "Wrong %s cannot authorize a new offer" % field)
	var invalid := _pair()
	invalid.members[1].offers[0].valid_until = 1.0
	check(planner.propose(invalid).assignments.is_empty(), "An offer at its exact expiry is stale")
	invalid = _pair()
	invalid.members[0].offers[0].path_summary.side = []
	check(planner.propose(invalid).counters.offers_rejected > 0, "Malformed summary fields are rejected before numeric conversion")
	invalid = _pair()
	invalid.members[1].offers[0].role = {}
	check(planner.propose(invalid).assignments.is_empty(), "A dictionary cannot be coerced into a role name")
	invalid = _pair()
	invalid.members[1].offers[0].cost = NAN
	check(planner.propose(invalid).reason == &"invalid_snapshot", "Non-finite values are rejected at the pure boundary")
	invalid = _pair()
	invalid.hidden_target = RefCounted.new()
	check(planner.propose(invalid).reason == &"invalid_snapshot", "Object references cannot enter the planner snapshot")
	var busy: Array = []
	for actor_id in range(1, 7):
		var offers: Array = []
		for role in [&"inspect_left", &"inspect_right", &"front_support", &"flank", &"search_sector", &"independent_position"]:
			offers.append(_offer(actor_id, role, Vector3(actor_id * 3, 0, offers.size() * 3), "%d_%s" % [actor_id, role]))
		busy.append(_member(actor_id, offers))
	var crowded := _snapshot(busy)
	crowded.requests = [_request(6)]
	var result: Dictionary = planner.propose(crowded, {"max_pair_trials": 9999})
	check(result.counters.pair_trials > 0 and result.counters.pair_trials <= 36, "All four strategy queues share one hard total of at most 36 trials")
	check(planner.propose(crowded, {"max_pair_trials": 7}).counters.pair_trials <= 7, "A smaller caller budget also applies across every strategy and extension")
	check(planner.propose(crowded, {"max_pair_trials": 0}).assignments.is_empty(), "Zero combination budget never grants a tactical assignment")
	result = planner.propose(crowded, {"max_conflict_checks": 1})
	check(result.counters.conflict_checks <= 1 and result.counters.conflict_limit_reached, "Compatibility checks have an independent hard bound and fail conservatively")
	for field in [&"plan_id", &"assignment_id", &"expires_at", &"release_at", &"phase_id"]:
		check(not first.has(field) and first.assignments.all(func(assignment): return not assignment.has(field)), "Planner does not manufacture %s" % field)
