extends "res://tests/enemy/enemy_team_posture_planner_test.gd"

func _run() -> void:
	for kind: StringName in [&"reload", &"retreat"]:
		var snapshot := _support_fixture(kind)
		var result: Dictionary = planner.propose(snapshot)
		check(result.tactic == kind and result.assignments.size() == 2 and result.support_links.size() == 1, "%s pairs the actual action owner with a distinct shooter" % kind)
		check(result.required_participants == [1] and result.support_links[0].provider_id == 1 and result.support_links[0].beneficiary_id == 2, "%s synchronizes only its necessary shooter" % kind)
		check(result.counters.pair_trials <= 36 and result.counters.conflict_checks <= 2048, "%s shares the existing finite proposal budget" % kind)
	var snapshot := _support_fixture(&"reload")
	snapshot.members[0].status.rounds = 0
	check(planner.propose(snapshot).assignments.is_empty(), "Empty magazines cannot be selected as promised cover")
	snapshot = _support_fixture(&"reload")
	snapshot.members[2].status.reloading = true
	check(planner.propose(snapshot).assignments.is_empty(), "Another actual reload prevents a new nonurgent reload schedule")
	snapshot = _support_fixture(&"reload")
	snapshot.members[0].status.needs_fire_handoff = true
	check(planner.propose(snapshot).assignments.is_empty(), "A shooter already due for relief cannot open a new support dependency")
	snapshot = _support_fixture(&"retreat")
	snapshot.members[1].personal_baseline.preparation_ready = false
	check(planner.propose(snapshot).reason == &"personal_baseline_pending", "A hurt member's pending defensive geometry prevents a premature long assignment")
	snapshot = _support_fixture(&"retreat")
	snapshot.members[1].offers[0].path_summary.defensive_need = false
	check(planner.propose(snapshot).assignments.is_empty(), "Support credit cannot manufacture a retreat without a real defensive need")
	var cyclic: Array = [{"provider_id": 1, "beneficiary_id": 2, "kind": &"advance", "requires_ready": true}, {"provider_id": 2, "beneficiary_id": 1, "kind": &"reload", "requires_ready": true}]
	check(not planner._support_links_valid(cyclic, [1, 2]), "Mutual support dependencies cannot deadlock the team")
	check(not planner._support_links_valid([cyclic[0], cyclic[0]], [1, 2]), "One beneficiary cannot accept conflicting duplicate promises")
	var occupied := _support_fixture(&"reload")
	var original: Dictionary = planner.propose(occupied)
	occupied.current_plan = _plan(occupied, original)
	occupied.current_plan.tactic = &"hold"
	occupied.current_plan.segment_boundary = false
	occupied.current_plan.support_links = []
	for entry: Dictionary in occupied.current_plan.assignments:
		entry.accepted = true
		entry.segment_boundary = entry.actor_id == 2
		if entry.actor_id == 2:
			entry.role = &"team_position"
			entry.owner_action = &"cooperate"
	occupied.members[1].eligible_roles.append(&"team_position")
	var before_revision: Dictionary = occupied.current_plan.duplicate(true)
	var revised: Dictionary = planner.propose(occupied)
	check(revised.operation == &"revise" and revised.changed_actor_ids == [2] and revised.assignments.size() == 1, "A held member can accept assistance without interrupting another committed team segment")
	check(revised.get("support_links", []).size() == 1 and revised.support_links[0].provider_id == 1 and occupied.current_plan == before_revision, "A local revision uses a distinct established provider without mutating the current plan")
	occupied.current_plan.assignments[1].segment_boundary = false
	check(planner.propose(occupied).operation != &"revise", "A committed beneficiary must reach its own real boundary before local reassignment")
	snapshot = _support_fixture(&"reload")
	var result: Dictionary = planner.propose(snapshot)
	snapshot.current_plan = _plan(snapshot, result)
	snapshot.current_plan.support_links = result.support_links.duplicate(true)
	snapshot.members[0].status.rounds = 2
	snapshot.members[0].status.needs_fire_handoff = true
	var spare := _offer(3, &"front_support", Vector3(5, 0, -3), "replacement", 2.0)
	spare.team_config_revision = snapshot.team_config_revision
	spare.path_summary.expected_fire_seconds = 2.0
	snapshot.members[2].offers = [spare]
	snapshot.members[2].eligible_roles = [&"front_support"]
	result = planner.propose(snapshot)
	check(result.operation == &"handoff" and result.assignments[0].actor_id == 3 and result.handoff.previous_provider_id == 1, "A low-ammo provider keeps its place while a real spare is proposed")
	check(snapshot.current_plan.support_links[0].provider_id == 1, "A proposed handoff does not falsely replace actual support")
	var occupied_spare := snapshot.duplicate(true)
	var replacement: Dictionary = result.assignments[0].duplicate(true)
	replacement.merge({"accepted": true, "execution_valid": true, "segment_boundary": true, "assignment_id": 30, "assignment_revision": 1, "expires_at": occupied_spare.current_plan.expires_at}, true)
	occupied_spare.current_plan.assignments.append(replacement)
	occupied_spare.members[2].actual_support = {"fire_ready": true, "measured_support_seconds": 1.0}
	var existing_handoff: Dictionary = planner.propose(occupied_spare)
	check(existing_handoff.operation == &"handoff" and existing_handoff.assignments.is_empty() and existing_handoff.handoff.get("existing_replacement", false), "A full squad can transfer fire to an existing ready post without a duplicate assignment")
	snapshot.members[0].status.needs_fire_handoff = false
	result = planner.propose(snapshot)
	check(result.operation in [&"keep", &"extend"] and not result.has("handoff") and snapshot.current_plan.support_links[0].provider_id == 1, "The configured threshold retains the actual provider; an extra front post is not a false handoff")
	snapshot.members.remove_at(0)
	result = planner.propose(snapshot)
	check(result.operation == &"repair" and result.assignments[0].actor_id == 3, "A departed shooter is repaired locally while the beneficiary retains its original slot")
	snapshot.current_plan.support_links = cyclic
	check(planner.propose(snapshot).reason == &"invalid_current_plan", "Invalid dependency cycles are rejected before continuity can preserve them")
	snapshot = _support_fixture(&"reload")
	result = planner.propose(snapshot)
	snapshot.current_plan = _plan(snapshot, result)
	snapshot.current_plan.support_links = result.support_links.duplicate(true)
	snapshot.members.remove_at(1)
	check(planner.propose(snapshot).reason == &"beneficiary_unavailable", "A departed beneficiary's reload is not reassigned to an unrelated healthy member")
	var board = preload("res://scripts/enemy/services/enemy_cooperation.gd").new()
	var source := {"position": Vector3.ZERO, "front_axis": Vector3.RIGHT}
	var summary := {"tactical_key": "frame", "tactical_anchor": Vector3.ZERO, "tactical_axis": Vector3.RIGHT, "side": -1}
	var coordinator = preload("res://scripts/enemy/services/squad_coordination.gd").new()
	check(coordinator._coordination_frame_valid(summary, source, &"front_support", Vector3(-3, 0, 0), true), "Strong ordinary covering fire is legal on either actual side of the target")
	check(not coordinator._coordination_frame_valid(summary, source, &"front_support", Vector3(-3, 0, 0)) and not coordinator._coordination_frame_valid(summary, source, &"flank", Vector3(3, 0, 0), true), "General support preserves the front and real opposite-flank constraints")
	print("TEAM SUPPORT PLANNER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _support_fixture(kind: StringName) -> Dictionary:
	var snapshot := _deployment(&"concentrate")
	var role: StringName = &"assisted_reload" if kind == &"reload" else &"assisted_retreat"
	var offer: Dictionary = snapshot.members[1].offers[0]
	offer.role = role
	offer.owner_action = &"reload" if kind == &"reload" else &"covering_retreat"
	offer.path_summary.action_seconds = 1.2
	offer.path_summary.defensive_need = true
	snapshot.members[1].eligible_roles = [role]
	for member: Dictionary in snapshot.members:
		member.status.magazine_capacity = 10
		member.status.needs_fire_handoff = false
	return snapshot
