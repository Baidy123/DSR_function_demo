extends RefCounted

## Owned by one explicit SquadController, or the area's legacy adapter.
## The area owns observations, physical reservations and the only active clock.
## This service owns tactical leases, proposals, assignments and their progress.
const TeamPlanner = preload("res://scripts/enemy/services/enemy_team_planner.gd")
var _environment: WeakRef
var _members: Dictionary = {}
var _teams: Dictionary = {}
var _team_by_member: Dictionary = {}
var configuration: Dictionary = {}
var configuration_revision := 0
## Diagnostics; durations and counts do not participate in tactical decisions.
var last_advance_usec := 0
var planning_count := 0
var environment:
	get: return _environment.get_ref() if _environment != null else null
var elapsed: float:
	get: return environment.elapsed
var generation: int:
	get: return environment.generation
var relation_revision: int:
	get: return environment.relation_revision
var _serial: int:
	get: return environment._serial
	set(value): environment._serial = value
var revision: int:
	get: return environment.revision
	set(value): environment.revision = value
var _reports: Dictionary:
	get: return environment._reports
var _relations: Dictionary:
	get: return environment._relations
var _inspection_reports: Dictionary:
	get: return environment._inspection_reports
var _claims: Dictionary = {}
var _flank_rounds: Dictionary = {}
var _coordination_sources: Dictionary = {}
var _coordination_source_pool: Dictionary = {}
var _coordination_receipts: Dictionary = {}
var _coordination_offers: Dictionary = {}
var _coordination_baselines: Dictionary = {}
var _coordination_plans: Dictionary = {}
var _coordination_environments: Dictionary = {}
var _coordination_due: Dictionary = {}
var _coordination_failures: Array[Dictionary] = []
var _coordination_counters: Dictionary = {}
var _coordination_checked: Dictionary = {}
var _recommendations: Dictionary = {}
var _recommendation_cooldowns: Dictionary = {}
var _team_planner = TeamPlanner.new()
const COORDINATION_PERIOD := 0.2 # Implementation default, not a user constraint.
const COORDINATION_ACCEPT_SECONDS := 1.0
const COORDINATION_WAIT_SECONDS := 2.0
const COORDINATION_MAX_SECONDS := 20.0
const COORDINATION_SOURCE_DISTANCE := 0.5
const COORDINATION_REPORT_SECONDS := 0.35
const FLANK_SIDE_MARGIN := 0.5
const FLANK_DESTINATION_SPACING := 1.2
const FLANK_SEPARATION_COSINE := -0.5 # cos(120 degrees), horizontal directions.
const FLANK_GEOMETRY_MEMBER_STEP := 0.5
const FLANK_GEOMETRY_TARGET_STEP := 0.25


func bind_environment(board) -> void:
	_environment = weakref(board)

func configure_profile(value: Dictionary) -> void:
	reset()
	configuration = value.duplicate(true)
	configuration_revision += 1

func sync_members(members: Dictionary, teams: Dictionary, mapping: Dictionary) -> void:
	_members = members
	_teams = teams
	_team_by_member = mapping

func registered_member_count() -> int:
	return _members.size()

## The area sees ownership/validity only, never our mutable assignment dictionary.
func reservation_current(reservation_id: int, assignment_id: int, owner_id: int) -> bool:
	var entry := _assignment_for_owner(owner_id)
	return not entry.is_empty() and reservation_id in [entry.reservation_id, entry.get("pending_reservation_id", 0)] and entry.assignment_id == assignment_id

func member_faction(actor: Node) -> StringName:
	return environment.member_faction(actor)

func member_group(actor: Node) -> StringName:
	return environment.member_group(actor)

func advance() -> void:
	var started := Time.get_ticks_usec()
	for token in _claims.keys():
		var entry: Dictionary = _claims[token]
		var context = _context(entry.owner_id)
		if elapsed >= entry.expires_at or context == null or not context.cooperation_enabled() or not context.can_use_action(entry.owner_action) or context.cooperation_target_id() != entry.target_id:
			_claims.erase(token)
			revision += 1
	_maintain_flank_rounds()
	_maintain_recommendations()
	_advance_coordination()
	last_advance_usec = Time.get_ticks_usec() - started

func reset() -> void:
	for team_id in _coordination_plans.keys(): _drop_coordination_plan(team_id, &"reset")
	_claims.clear()
	_flank_rounds.clear()
	_clear_coordination()

func release_member(id: int) -> void:
	_recommendations.erase(id)
	_coordination_baselines.erase(id)
	_coordination_offers.erase(id)
	_invalidate_coordination_member(id, &"member_released")
	for token in _claims.keys():
		if _claims[token].owner_id == id or _claims[token].get("beneficiary_id", 0) == id: _claims.erase(token)

func invalidate_member(id: int) -> void:
	_coordination_offers.erase(id)
	_coordination_baselines.erase(id)
	_invalidate_coordination_member(id, &"member_version_changed")

func clear_execution(id: int) -> void:
	var advice: Dictionary = _recommendations.get(id, {})
	if advice.get("accepted", false) and not environment.reservation_values().any(func(entry): return entry.owner_id == id and entry.phase == &"pending" and entry.get("recommendation_id") == advice.recommendation_id):
		_recommendations.erase(id)
	for token in _claims.keys():
		if int(_claims[token].owner_id) == id: _claims.erase(token)

func crossed_flank(context, previous: Vector3, current: Vector3) -> bool:
	for round: Dictionary in _flank_rounds.values():
		if _flank_round_matches(round, context) and _flank_opposite(round, previous) != _flank_opposite(round, current): return true
	return false

func append_snapshot(context, target: int, result: Dictionary, include_claims: bool = true) -> void:
	var id: int = context.actor.get_instance_id()
	for claim in _claims.values():
		if not include_claims and (claim.kind not in [&"advance", &"flank"] or claim.owner_id == id): continue
		if claim.target_id != target or not _claim_valid(claim) or not can_cooperate(claim.owner_id, id): continue
		var copy: Dictionary = claim.duplicate(true)
		copy.remaining = claim.expires_at - elapsed
		if include_claims: result.claims.append(copy)
		if claim.kind in [&"advance", &"flank"] and claim.owner_id != id:
			var request := copy.duplicate(true)
			request.request_id = claim.id
			request.beneficiary_id = claim.owner_id
			request.lane_id = &"target"
			result.requests.append(request)
	var source := coordination_source(context, target)
	# Only accepted plan requests are appended below. Raw status requests were
	# already projected by the area, so an absent plan needs no second member scan.
	if not source.is_empty() and _coordination_plans.has(source.team_id):
		for need: Dictionary in _coordination_requests(_coordination_team_members(source.team_id), source):
			if not need.get("accepted", false) or need.actor_id == id: continue
			result.requests.append({"id": need.request_id, "request_id": need.request_id, "kind": need.kind, "preparing": not need.get("actual", false),
				"target_id": target, "beneficiary_id": need.actor_id, "lane_id": &"target",
				"position": _context(need.actor_id).actor.global_position, "remaining": maxf(0.0, need.valid_until - elapsed)})


func _claim_valid(entry: Dictionary) -> bool:
	var owner = _context(entry.owner_id)
	var valid: bool = entry.expires_at > elapsed and owner != null and is_instance_valid(owner.actor) and owner.actor.is_inside_tree() and owner.cooperation_enabled() and owner.can_use_action(entry.owner_action) and owner.cooperation_target_id() == entry.target_id
	if valid and entry.kind == &"inspect_end":
		var evidence := inspection_evidence(owner, entry.target_id)
		if evidence.is_empty() or int(evidence.id) != int(entry.get("inspection_id", -1)) or entry.get("domain", "") != _domain(owner.actor): return false
		var body = entry.get("cover").get_ref() if entry.get("cover") is WeakRef else null
		if not is_instance_valid(body) or not body is StaticBody3D or (body.collision_layer & 1) == 0 or not is_instance_valid(owner.navigation_region) or not owner.navigation_region.is_ancestor_of(body): return false
		var box = body.get_node_or_null("CollisionShape3D")
		return box is CollisionShape3D and not box.disabled and box.shape is BoxShape3D and box.global_transform == entry.get("cover_transform") and box.shape.size == entry.get("cover_size")
	if not valid or entry.kind != &"flank": return valid
	var round: Dictionary = _flank_rounds.get(entry.get("flank_round_id", 0), {})
	return not round.is_empty() and _flank_round_matches(round, owner)

func _drop_inspection_claims(inspection_id: int) -> void:
	for token in _claims.keys():
		if int(_claims[token].get("inspection_id", -1)) == inspection_id: _claims.erase(token)
	revision += 1

## Called only for an acquired observation. Input uses the observer's clock;
## returned/shared values use board time and never gain life when read again.

func _inspection_eligible_members(context, target: int) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var owner: int = context.actor.get_instance_id()
	for id in _members:
		var other = _context(id)
		if other == null or not can_cooperate(id, owner) or not other.cooperation_enabled() or other.cooperation_target_id() != target or not other.is_alerted or not other.actor.can_move(): continue
		members.append({"id": id, "position": other.actor.global_position})
	return members

## Radio membership alone cannot provide a second capable investigator.

func inspection_eligible_count(context, target: int) -> int:
	return _inspection_eligible_members(context, target).size()

func inspection_end(context, geometry: Dictionary) -> int:
	if not context.cooperation_enabled(): return 0
	var evidence := inspection_evidence(context, geometry.target_id)
	if evidence.is_empty() or int(evidence.id) != int(geometry.inspection_id): return 0
	var owner: int = context.actor.get_instance_id()
	var occupied: Dictionary = {}
	for entry: Dictionary in _claims.values():
		if entry.kind != &"inspect_end" or int(entry.get("inspection_id", -1)) != int(evidence.id) or not _claim_valid(entry) or not can_cooperate(entry.owner_id, owner): continue
		if int(entry.owner_id) == owner: return int(entry.end)
		occupied[int(entry.end)] = int(entry.owner_id)
	var members := _inspection_eligible_members(context, int(geometry.target_id))
	if members.size() < 2: return 0
	var best: Dictionary = {}
	var best_cost := INF
	for first: Dictionary in members:
		for second: Dictionary in members:
			if first.id == second.id: continue
			if occupied.has(-1) and occupied[-1] != first.id: continue
			if occupied.has(1) and occupied[1] != second.id: continue
			var cost: float = first.position.distance_to(geometry.ends[-1].entry) + second.position.distance_to(geometry.ends[1].entry)
			if cost < best_cost - 0.001 or (absf(cost - best_cost) <= 0.001 and int(first.id) < int(best.get(-1, 9223372036854775807))):
				best_cost = cost
				best = {-1: first.id, 1: second.id}
	for end in [-1, 1]:
		if best.get(end, 0) == owner and not evidence.checked_ends.has(end): return end
	return 0

func inspection_revision(context, inspection_id: int) -> int:
	var state: Array = [generation, relation_revision, inspection_id]
	for id in _members:
		var other = _context(id)
		if other == null or not can_cooperate(id, context.actor.get_instance_id()) or not other.cooperation_enabled(): continue
		state.append([id, other.cooperation_target_id(), other.is_alerted, other.actor.can_move(), other.actor.global_position.snapped(Vector3.ONE * 0.5)])
	for entry: Dictionary in _claims.values():
		if entry.kind == &"inspect_end" and int(entry.get("inspection_id", -1)) == inspection_id and _claim_valid(entry): state.append([entry.owner_id, entry.end])
	var evidence := inspection_evidence(context, context.cooperation_target_id())
	state.append(evidence.get("checked_ends", []))
	return hash(state)

func inspection_partner_ready(context, token: Dictionary) -> bool:
	if not _claim_valid(token): return false
	for entry: Dictionary in _claims.values():
		if entry.kind != &"inspect_end" or entry.owner_id == context.actor.get_instance_id() or int(entry.get("inspection_id", -1)) != int(token.inspection_id) or not _claim_valid(entry): continue
		if not can_cooperate(entry.owner_id, context.actor.get_instance_id()): continue
		var other = _context(entry.owner_id)
		if int(entry.get("phase", 0)) >= 2 and other.actor.can_move() and other.actor.global_position.distance_to(entry.entry) <= 0.35: return true
	return false

func complete_inspection(context, token: Dictionary) -> void:
	if not _claim_valid(token): return
	if context.actor.global_position.distance_to(token.peek) > 0.35: return
	var known: Vector3 = token.get("geometry", {}).get("known", Vector3.INF)
	if not known.is_finite() or not context.perception.can_observe_position(known): return
	for report: Dictionary in _inspection_reports.values():
		if int(report.id) == int(token.inspection_id) and not report.checked_ends.has(int(token.end)): report.checked_ends.append(int(token.end))
	release(context, token)

func flank_opportunity(context) -> Dictionary:
	var result := {"round_id": 0, "anchor": Vector3.INF, "front_axis": Vector3.ZERO, "capacity": 0, "remaining_slots": 0}
	if not context.cooperation_enabled(): return result
	var target: int = context.cooperation_target_id()
	var evidence: Dictionary = context.cooperation_target_evidence()
	if target == 0 or not _flank_evidence_live(context, evidence): return result
	var members := _flank_members(context, target)
	return _flank_opportunity_for_members(context, evidence, members)

## Only geometric inputs invalidate the bounded spatial queue. Report IDs,
## timestamps and firing cadence still reprice live candidates without clearing
## their geometry. Quantization is an invalidation hint, never an input to paths,
## occupancy, destination validation or actual movement.

func flank_geometry_revision(context) -> int:
	if not context.cooperation_enabled(): return 0
	var target: int = context.cooperation_target_id()
	var evidence: Dictionary = context.cooperation_target_evidence()
	if target == 0 or not _flank_evidence_live(context, evidence): return 0
	var members := _flank_members(context, target)
	if members.size() < 2: return 0
	members.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.id) < int(b.id))
	var key: Array = [generation, member_faction(context.actor), member_group(context.actor), target,
		_geometry_cell(evidence.position, FLANK_GEOMETRY_TARGET_STEP)]
	for member: Dictionary in members:
		key.append([member.id, _geometry_cell(member.position, FLANK_GEOMETRY_MEMBER_STEP)])
	var opportunity := _flank_opportunity_for_members(context, evidence, members)
	# Occupancy uses real body positions, so crossing a quota plane invalidates
	# immediately even when both positions fall inside the same half-metre cell.
	key.append([opportunity.round_id, opportunity.capacity, opportunity.remaining_slots])
	if opportunity.round_id != 0: key.append([opportunity.anchor, opportunity.front_axis])
	var slots: Array = []
	var id: int = context.actor.get_instance_id()
	for entry: Dictionary in _claims.values():
		if entry.target_id != target or entry.kind not in [&"advance", &"flank"] or not _claim_valid(entry) or not can_cooperate(entry.owner_id, id): continue
		slots.append([entry.id, entry.owner_id, entry.kind, entry.lane_id, entry.get("flank_destination", Vector3.INF)])
	slots.sort_custom(func(a: Array, b: Array): return int(a[0]) < int(b[0]))
	key.append(slots)
	return hash(key)

func _geometry_cell(position: Vector3, step: float) -> Vector3i:
	return Vector3i(roundi(position.x / step), roundi(position.y / step), roundi(position.z / step))

func _flank_opportunity_for_members(context, evidence: Dictionary, members: Array[Dictionary]) -> Dictionary:
	var result := {"round_id": 0, "anchor": Vector3.INF, "front_axis": Vector3.ZERO, "capacity": 0, "remaining_slots": 0}
	if members.size() < 2: return result
	var capacity := floori(members.size() / 2.0)
	for round: Dictionary in _flank_rounds.values():
		if not _flank_round_matches(round, context): continue
		# Do not rotate or start a second frame while the first round is alive.
		if evidence.position.distance_to(round.anchor) > 2.0: return result
		return {"round_id": round.id, "anchor": round.anchor, "front_axis": round.front_axis,
			"capacity": capacity, "remaining_slots": maxi(0, capacity - _flank_occupants(round, members).size()),
			"expires_at": round.expires_at, "remaining_seconds": maxf(0.0, round.expires_at - elapsed)}
	var anchor: Vector3 = evidence.position
	var axis := Vector3.ZERO
	var directions: Array[Vector3] = []
	for member: Dictionary in members:
		var radial: Vector3 = member.position - anchor
		radial.y = 0.0
		axis += radial
		directions.append(radial.normalized())
	if axis.is_zero_approx(): return result
	axis = axis.normalized()
	for member: Dictionary in members:
		if (member.position - anchor).dot(axis) <= FLANK_SIDE_MARGIN: return result
	for first in directions.size():
		for second in range(first + 1, directions.size()):
			if directions[first].dot(directions[second]) <= FLANK_SEPARATION_COSINE: return result
	return {"round_id": 0, "anchor": anchor, "front_axis": axis, "capacity": capacity, "remaining_slots": capacity}

func _flank_evidence_live(context, evidence: Dictionary) -> bool:
	return not evidence.is_empty() and evidence.get("target_id", 0) == context.cooperation_target_id() and evidence.get("position", Vector3.INF).is_finite() and float(evidence.get("valid_until", -INF)) > context.evidence_elapsed_seconds

func _flank_members(context, target: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var id: int = context.actor.get_instance_id()
	for other_id in _members:
		if not can_cooperate(other_id, id): continue
		var other = _context(other_id)
		if other == null or not other.actor.is_inside_tree() or other.cooperation_target_id() != target: continue
		var activity: Dictionary = _members[other_id].activity
		if activity.is_empty() or int(activity.get("target_id", 0)) != target or elapsed - float(activity.updated_at) > 0.35: continue
		result.append({"id": other_id, "position": other.actor.global_position})
	return result

func _flank_round_matches(round: Dictionary, context) -> bool:
	var id: int = context.actor.get_instance_id()
	if round.expires_at <= elapsed or round.generation != generation or round.target_id != context.cooperation_target_id(): return false
	if not _members.has(id) or not can_share_intel(id, id) or not context.actor.is_inside_tree(): return false
	return round.group == member_group(context.actor) and (round.faction == member_faction(context.actor) or _relations.get([round.faction, member_faction(context.actor)], &"") == &"allied")

func _flank_opposite(round: Dictionary, position: Vector3) -> bool:
	return (position - round.anchor).dot(round.front_axis) < -FLANK_SIDE_MARGIN

func _flank_occupants(round: Dictionary, members: Array[Dictionary]) -> Dictionary:
	var occupied: Dictionary = {}
	for member: Dictionary in members:
		if _flank_opposite(round, member.position): occupied[member.id] = true
	for entry: Dictionary in _claims.values():
		if entry.kind == &"flank" and entry.get("flank_round_id", 0) == round.id and _claim_valid(entry): occupied[entry.owner_id] = true
	return occupied

func _claim_flank(context, task: Dictionary) -> Dictionary:
	_maintain_flank_rounds()
	var id: int = context.actor.get_instance_id()
	var target: int = context.cooperation_target_id()
	if int(task.get("target_id", target)) != target or not context.can_use_action(task.get("owner_action", &"cooperate")): return {}
	var opportunity := flank_opportunity(context)
	if opportunity.capacity <= 0: return {}
	var anchor: Vector3 = task.get("flank_anchor", Vector3.INF)
	var axis: Vector3 = task.get("flank_axis", Vector3.ZERO)
	var destination: Vector3 = task.get("flank_destination", Vector3.INF)
	var proposed_round: int = task.get("flank_round_id", 0)
	if not anchor.is_finite() or not axis.is_finite() or not destination.is_finite(): return {}
	if anchor.distance_to(opportunity.anchor) > 0.1 or axis.distance_to(opportunity.front_axis) > 0.01: return {}
	if proposed_round != 0 and proposed_round != opportunity.round_id: return {}
	if (destination - opportunity.anchor).dot(opportunity.front_axis) >= -FLANK_SIDE_MARGIN: return {}
	for existing: Dictionary in _claims.values():
		if existing.kind != &"flank" or existing.target_id != target or not _claim_valid(existing) or not can_cooperate(existing.owner_id, id): continue
		if existing.owner_id == id:
			return existing.duplicate(true) if existing.flank_destination.distance_to(destination) < 0.05 else {}
		if existing.flank_destination.distance_to(destination) < FLANK_DESTINATION_SPACING: return {}
	for member: Dictionary in _flank_members(context, target):
		if member.id != id and member.position.distance_to(destination) < FLANK_DESTINATION_SPACING: return {}
	if opportunity.remaining_slots <= 0: return {}
	var duration: float = task.get("duration", 4.0)
	if not is_finite(duration) or duration <= 0.0: return {}
	var round_id: int = opportunity.round_id
	if round_id == 0:
		_serial += 1
		round_id = _serial
		_flank_rounds[round_id] = {"id": round_id, "target_id": target, "anchor": opportunity.anchor,
			"front_axis": opportunity.front_axis, "faction": member_faction(context.actor), "group": member_group(context.actor),
			"generation": generation, "expires_at": elapsed + duration}
	var round: Dictionary = _flank_rounds[round_id]
	_serial += 1
	var value := task.duplicate(true)
	value.merge({"id": _serial, "owner_id": id, "target_id": target, "kind": &"flank", "lane_id": task.get("lane_id", &"opposite"),
		"position": context.actor.global_position, "generation": generation, "created_at": elapsed,
		"expires_at": minf(elapsed + duration, round.expires_at), "owner_action": task.get("owner_action", &"cooperate"),
		"flank_round_id": round_id, "flank_anchor": round.anchor, "flank_axis": round.front_axis, "flank_destination": destination}, true)
	_claims[_serial] = value
	revision += 1
	return value.duplicate(true)

func _discard_flank_round(round_id: int) -> void:
	for token in _claims.keys():
		if _claims[token].get("flank_round_id", 0) == round_id: _claims.erase(token)
	_flank_rounds.erase(round_id)
	revision += 1

## Execution maintenance only. A falling population first revokes departures
## that have not crossed; already moved bodies are never teleported back.

func _maintain_flank_rounds() -> void:
	for round_id in _flank_rounds.keys():
		var round: Dictionary = _flank_rounds[round_id]
		var representative = null
		var evidence_moved := false
		for id in _members:
			var member = _context(id)
			if member == null or not is_instance_valid(member.actor) or not _flank_round_matches(round, member): continue
			var evidence: Dictionary = member.cooperation_target_evidence()
			if _flank_evidence_live(member, evidence):
				if evidence.position.distance_to(round.anchor) > 2.0: evidence_moved = true
				if member.cooperation_enabled(): representative = member
		if representative == null or evidence_moved:
			_discard_flank_round(round_id)
			continue
		var members := _flank_members(representative, round.target_id)
		if members.size() < 2:
			_discard_flank_round(round_id)
			continue
		var crossed: Dictionary = {}
		for member: Dictionary in members:
			if _flank_opposite(round, member.position): crossed[member.id] = true
		var claims: Array[Dictionary] = []
		for token in _claims.keys():
			var entry: Dictionary = _claims[token]
			if entry.get("flank_round_id", 0) != round_id: continue
			if not _claim_valid(entry):
				_claims.erase(token)
				revision += 1
			else: claims.append(entry)
		claims.sort_custom(func(a: Dictionary, b: Dictionary):
			if crossed.has(a.owner_id) != crossed.has(b.owner_id): return crossed.has(a.owner_id)
			return int(a.id) < int(b.id))
		var unclaimed_crossed := crossed.duplicate()
		for entry: Dictionary in claims: unclaimed_crossed.erase(entry.owner_id)
		var slots: int = maxi(0, floori(members.size() / 2.0) - unclaimed_crossed.size())
		for index in range(slots, claims.size()):
			_claims.erase(claims[index].id)
			revision += 1

func claim(context, task: Dictionary) -> Dictionary:
	if not context.cooperation_enabled(): return {}
	var id: int = context.actor.get_instance_id()
	if not _members.has(id): register(context)
	if not _members.has(id) or _context(id) != context: return {}
	var target: int = task.get("target_id", context.cooperation_target_id())
	var kind: StringName = task.get("kind", &"")
	var lane: String = String(task.get("lane_id", ""))
	var point: Vector3 = task.get("position", context.actor.global_position)
	if target == 0 or kind.is_empty() or not point.is_finite(): return {}
	if kind == &"flank": return _claim_flank(context, task)
	if kind == &"inspect_end":
		var report := inspection_evidence(context, target)
		if report.is_empty() or int(report.id) != int(task.get("inspection_id", -1)) or report.checked_ends.has(int(task.get("end", 0))): return {}
		if int(task.get("end", 0)) not in [-1, 1] or task.get("geometry", {}).is_empty() or inspection_end(context, task.geometry) != int(task.end): return {}
	for existing in _claims.values():
		if not _claim_valid(existing) or existing.target_id != target or not can_cooperate(existing.owner_id, id): continue
		if existing.owner_id == id and existing.kind == kind and String(existing.lane_id) == lane: return existing.duplicate(true)
		var collision: bool = existing.kind == kind and not lane.is_empty() and String(existing.lane_id) == lane
		if kind == &"search" and existing.kind == kind:
			collision = existing.position.distance_to(point) < float(task.get("radius", 1.0))
		if kind == &"reload" and existing.kind == kind: collision = true
		if collision: return {}
	_serial += 1
	var value := task.duplicate(true)
	value.merge({"id": _serial, "owner_id": id, "target_id": target, "kind": kind, "lane_id": lane, "position": point,
		"generation": generation, "created_at": elapsed, "expires_at": elapsed + maxf(0.1, float(task.get("duration", 4.0))),
		"owner_action": task.get("owner_action", context.utility_current.get("id", &"cooperate"))}, true)
	if kind == &"inspect_end":
		value.domain = _domain(context.actor)
		value.expires_at = minf(value.expires_at, float(inspection_evidence(context, target).valid_until))
	_claims[_serial] = value
	revision += 1
	return value.duplicate(true)

func update_claim(context, token: Dictionary, state: Dictionary) -> bool:
	var id: int = token.get("id", 0)
	if not _claims.has(id) or token.get("generation", -1) != generation: return false
	if _claims[id].kind == &"flank":
		_maintain_flank_rounds()
		if not _claims.has(id): return false
	var entry: Dictionary = _claims[id]
	if entry.owner_id != context.actor.get_instance_id() or not _claim_valid(entry): return false
	# Status cannot renew evidence or impersonate measured ready fire.
	for key in [&"phase", &"progress", &"position"]:
		if state.has(key):
			if key == &"phase" and entry.get(key) != state[key]: revision += 1
			entry[key] = state[key]
	return true

func release(context, token: Dictionary) -> void:
	var id: int = token.get("id", 0)
	if _claims.has(id) and _claims[id].owner_id == context.actor.get_instance_id():
		_claims.erase(id)
		revision += 1

func search_available(context, point: Vector3, radius: float) -> bool:
	var id: int = context.actor.get_instance_id()
	var footprint := _reservation_footprint(context, point)
	for reservation: Dictionary in environment.reservation_values():
		if reservation.owner_id == id or not _reservation_valid(reservation) or not can_share_space(id, reservation.owner_id): continue
		for projection: Dictionary in _reservation_projections(reservation):
			var occupied := _reservation_footprint(_context(reservation.owner_id), projection.position)
			if _reservation_geometry_conflict(footprint, occupied): return false
	if not context.cooperation_enabled(): return true
	var target: int = context.cooperation_target_id()
	for item in _claims.values():
		if item.owner_id != id and item.kind == &"search" and item.target_id == target and _claim_valid(item) and can_cooperate(item.owner_id, id) and item.position.distance_to(point) < radius: return false
	return true

func reload_opportunity(context) -> Dictionary:
	var result := {"allowed": false, "support_seconds": 0.0, "provider_id": 0, "request_id": 0}
	if not context.cooperation_enabled(): return result
	var id: int = context.actor.get_instance_id()
	var data: Dictionary = context.cooperation_snapshot()
	for item in data.claims:
		if item.kind == &"reload" and item.owner_id != id: return result
	for member in data.members:
		if member.id != id and member.get("can_cooperate", false) and member.get("reloading", false): return result
	for support in data.supports + data.threats:
		if support.owner_id == id: continue
		if float(support.support_seconds) > float(result.support_seconds):
			result.support_seconds = support.support_seconds
			result.provider_id = support.owner_id
	result.allowed = float(result.support_seconds) >= maxf(0.01, context.setting(&"cooperation", &"reload_min_support_seconds", 0.5))
	return result

func candidate_seconds(context, candidate: Dictionary) -> float:
	if not context.cooperation_enabled(): return 0.0
	var horizon: float = context.utility_horizon_seconds
	var outcome: Dictionary = candidate.get("outcome", {})
	var explicit: float = maxf(0.0, float(outcome.get("cooperation_seconds", 0.0)))
	var task: Dictionary = candidate.get("cooperation", {})
	var data: Dictionary = context.cooperation_snapshot()
	var id: int = context.actor.get_instance_id()
	var available: float = maxf(0.0, horizon - float(outcome.get("unavailable_seconds", horizon)))
	var self_status: Dictionary = _members.get(id, {}).get("status", {})
	var support_time: float = float(task.get("support_seconds", available if self_status.get("ready", false) else 0.0))
	var start: float = clampf(float(task.get("estimated_start_seconds", 0.0)), 0.0, horizon)
	support_time = maxf(0.0, minf(support_time, horizon - start))
	var candidate_moving := _candidate_moves(context, candidate)
	# An ordinary moving option inherits the currently measured fire state, not
	# permission to keep firing after it starts walking. Explicit arrival plans
	# retain their own delayed, stationary support estimate.
	if task.is_empty() and candidate_moving and not context.fire.fire_while_moving: support_time = 0.0
	# Candidate predictions cannot promise more fire than the current magazine/burst.
	if context.actor.can_use_firearms():
		var shot_window: float = context.fire.burst_window_seconds(candidate.get("support_intent", false) or task.get("kind", &"") == &"support")
		if context.actor.ammo.is_reloading: shot_window = 0.0
		support_time = minf(support_time, shot_window)
	var quality: float = clampf(float(task.get("quality", 1.0)), 0.0, 1.0)
	var gain := explicit
	# A geometrically useful move can benefit while travelling even when the
	# covering magazine will be empty on arrival. Count the measured overlap,
	# never the promise of a claim, and do not discount the route's exposure.
	if task.get("movement_qualified", false):
		var move_start: float = clampf(float(task.get("movement_start_seconds", horizon)), 0.0, horizon)
		var move_end: float = minf(horizon, move_start + maxf(0.0, float(task.get("movement_seconds", 0.0))))
		for support in data.supports:
			if support.owner_id == id or support.get("moving", false) or support.get("lane_id", &"target") != &"target": continue
			var overlap: float = maxf(0.0, minf(move_end, float(support.support_seconds)) - move_start)
			gain = maxf(gain, overlap * quality)
	for request in data.requests:
		if request.beneficiary_id == id: continue
		if has_team_binding(context) and request.get("preparing", false): continue
		if task.get("request_id", 0) != 0 and task.request_id != request.request_id: continue
		if String(task.get("lane_id", "target")) != String(request.get("lane_id", "target")): continue
		var stationary_required := _request_requires_stationary(request)
		if stationary_required and candidate_moving: continue
		var covered := 0.0
		for support in data.supports:
			if support.owner_id == id: continue
			if stationary_required and support.get("moving", false): continue
			if String(support.get("lane_id", "target")) == String(task.get("lane_id", "target")):
				covered = maxf(covered, float(support.support_seconds))
		var end: float = minf(start + support_time, minf(horizon, float(request.get("remaining", horizon))))
		var missing: float = maxf(0.0, end - maxf(start, covered))
		gain = maxf(gain, missing * quality)
	if task.get("kind", &"") in [&"advance", &"flank", &"crossfire"] and task.get("position", Vector3.INF).is_finite():
		var evidence: Dictionary = context.cooperation_target_evidence()
		if not evidence.is_empty():
			var axis: Vector3 = task.position - evidence.position
			axis.y = 0.0
			for support in data.supports:
				if support.owner_id == id: continue
				var other: Vector3 = support.position - evidence.position
				other.y = 0.0
				if axis.is_zero_approx() or other.is_zero_approx(): continue
				var angle := rad_to_deg(axis.angle_to(other))
				if angle >= float(context.setting(&"cooperation", &"minimum_angle_degrees", 25.0)):
					var own_window: float = support_time if context.actor.can_use_firearms() else available
					var common_window: float = maxf(0.0, minf(start + own_window, float(support.support_seconds)) - start)
					gain = maxf(gain, common_window * minf(angle / 90.0, 1.0) * quality)
	return clampf(gain, 0.0, horizon) if is_finite(gain) else 0.0

func _candidate_moves(context, candidate: Dictionary) -> bool:
	if not candidate.get("route", {}).is_empty(): return true
	if float(candidate.get("cooperation", {}).get("movement_seconds", 0.0)) > 0.05: return true
	var destination: Dictionary = candidate.get("destination", {})
	var position: Vector3 = destination.get("position", destination.get("hide", Vector3.INF))
	if not position.is_finite(): return false
	var offset: Vector3 = position - context.actor.global_position
	return Vector2(offset.x, offset.z).length() > 0.15

func _request_requires_stationary(request: Dictionary) -> bool:
	return request.get("kind", &"") in [&"advance", &"flank", &"move"]

func support_pressure(context) -> float:
	if not context.cooperation_enabled(): return 0.0
	var data: Dictionary = context.cooperation_support_snapshot()
	var id: int = context.actor.get_instance_id()
	var covered_any := 0.0
	var covered_stationary := 0.0
	for support in data.supports:
		if support.owner_id == id or support.get("lane_id", &"target") != &"target": continue
		covered_any = maxf(covered_any, float(support.support_seconds))
		if not support.get("moving", false): covered_stationary = maxf(covered_stationary, float(support.support_seconds))
	var need := 0.0
	for request in data.requests:
		if request.beneficiary_id == id: continue
		var covered := covered_stationary if _request_requires_stationary(request) else covered_any
		need = maxf(need, maxf(0.0, float(request.get("remaining", 0.0)) - covered))
	return clampf(need / maxf(0.1, context.utility_horizon_seconds), 0.0, 1.0)


# Unified tactical bridge. Offers are published after the caller's read-only
# evaluation batch. None of these functions runs an action, navigates or fires.

func _clear_coordination() -> void:
	_coordination_baselines.clear()
	_recommendations.clear()
	_recommendation_cooldowns.clear()
	_coordination_sources.clear()
	_coordination_source_pool.clear()
	_coordination_receipts.clear()
	_coordination_offers.clear()
	_coordination_plans.clear()
	_coordination_environments.clear()
	_coordination_due.clear()
	_coordination_failures.clear()
	_coordination_counters.clear()
	_coordination_checked.clear()

func _coordination_team(context) -> int:
	if not _reservation_member_valid(context): return 0
	return int(_team_by_member.get(context.actor.get_instance_id(), 0))

func _coordination_key(team_id: int, target_id: int) -> String:
	return "%s:%s:%s" % [generation, team_id, target_id]

func _coordination_source_valid(context, source: Dictionary) -> bool:
	if _coordination_team(context) == 0: return false
	if typeof(source.get("source_id")) != TYPE_INT or source.source_id <= 0: return false
	if typeof(source.get("target_id")) != TYPE_INT or source.target_id < 0: return false
	if not source.get("position") is Vector3 or not source.position.is_finite(): return false
	if not _reservation_text(source.get("source")): return false
	if not _reservation_number(source.get("captured_at")) or not _reservation_number(source.get("valid_until")): return false
	if source.captured_at < 0.0 or source.captured_at > context.evidence_elapsed_seconds or source.valid_until <= context.evidence_elapsed_seconds: return false
	if source.target_id == 0:
		return source.source in [&"noise", &"sound"] and context.noise_search_origin.is_finite() and context.noise_search_origin.distance_squared_to(source.position) < 0.0001
	if source.target_id != context.cooperation_target_id(): return false
	# The Context event bridge is the source authority; this additionally checks
	# against acquired observation values, never the hidden target's transform.
	if source.source == &"visual":
		return context.sees_player and context.last_seen_position.distance_squared_to(source.position) < 0.0001
	if source.source in [&"visual_loss", &"close_cover_exact", &"inspection"]:
		var inspected := inspection_evidence(context, source.target_id)
		return not inspected.is_empty() and int(inspected.id) == source.source_id and inspected.position.distance_squared_to(source.position) < 0.0001
	if source.source in [&"shared_visual", &"observation_memory"]:
		if source.source == &"observation_memory" and source.valid_until > source.captured_at + maxf(0.1, context.setting(&"cooperation", &"cover_inspection_seconds", 20.0)) + 0.0001: return false
		for report: Dictionary in _reports.values():
			if int(report.id) == source.source_id and report.target_id == source.target_id and report.valid_until > elapsed and _inspection_domain_matches(context, report) and report.position.distance_squared_to(source.position) < 0.0001: return true
	return false

## Input timestamps use Context time. A duplicate source event cannot refresh
## its timestamp or deadline; only a genuinely acquired newer source can do so.

func publish_noise_source(context, position: Vector3) -> void:
	if not context.cooperation_enabled() or not position.is_finite(): return
	_serial += 1
	var captured: float = context.evidence_elapsed_seconds
	publish_coordination_source(context, {"source_id": _serial, "source": &"noise", "target_id": 0,
		"position": position, "captured_at": captured,
		"valid_until": captured + maxf(0.1, context.setting(&"cooperation", &"cover_inspection_seconds", 20.0))})

func publish_coordination_source(context, source: Dictionary) -> void:
	if not _coordination_source_valid(context, source): return
	var actor_id: int = context.actor.get_instance_id()
	var team_id := _coordination_team(context)
	var key := _coordination_key(team_id, source.target_id)
	var receipt_key: Array = [actor_id, source.target_id, StringName(source.source)]
	var receipt: Dictionary = _coordination_receipts.get(receipt_key, {})
	var same_event: bool = not receipt.is_empty() and receipt.source_id == source.source_id
	if same_event and receipt.team_id == team_id: return
	var offset: float = elapsed - context.evidence_elapsed_seconds
	var captured: float = float(receipt.captured_at) if same_event else maxf(0.0, float(source.captured_at) + offset)
	var deadline: float = float(receipt.valid_until) if same_event else float(source.valid_until) + offset
	if deadline <= elapsed: return
	_coordination_receipts[receipt_key] = {"source_id": source.source_id, "captured_at": captured, "valid_until": deadline, "team_id": team_id}
	var previous := _active_coordination_source(key)
	# A newer sight at another location contradicts an older investigation. An
	# older, longer-lived clue at the SAME frozen anchor remains a valid fallback.
	if not previous.is_empty() and captured < previous.captured_at and previous.position.distance_to(source.position) >= COORDINATION_SOURCE_DISTANCE: return
	var new_anchor: bool = previous.is_empty() or previous.position.distance_to(source.position) >= COORDINATION_SOURCE_DISTANCE
	var evidence_id: int = int(previous.get("evidence_id", 0))
	if new_anchor:
		_serial += 1
		evidence_id = _serial
		_drop_coordination_plan(team_id, &"new_evidence")
		_coordination_source_pool[key] = {}
	var anchor: Vector3 = source.position if new_anchor else previous.position
	var axis: Vector3 = _coordination_source_axis(team_id, anchor, source.target_id) if new_anchor else previous.front_axis
	var observed := {"source_id": source.source_id, "source": StringName(source.source),
		"observed_position": source.position, "captured_at": captured, "valid_until": deadline, "observer_id": actor_id}
	# One latest observation per source family, at most three entries per anchor.
	# Vision and investigation deliberately have different original deadlines.
	var family: StringName = &"investigation" if source.source in [&"visual_loss", &"close_cover_exact", &"inspection", &"observation_memory"] else (&"sound" if source.target_id == 0 else &"vision")
	var pool: Dictionary = _coordination_source_pool.get(key, {})
	var old: Dictionary = pool.get(family, {})
	if old.is_empty() or captured > old.captured_at or (captured == old.captured_at and deadline > old.valid_until): pool[family] = observed
	_coordination_source_pool[key] = pool
	_coordination_sources[key] = {"target_id": source.target_id, "position": anchor, "front_axis": axis,
		"flank_clustered": _coordination_clustered(team_id, anchor, axis, source.target_id) if new_anchor else previous.flank_clustered,
		"evidence_id": evidence_id, "generation": generation, "team_id": team_id}
	if new_anchor:
		_coordination_due[team_id] = elapsed
		revision += 1

func _active_coordination_source(key: String) -> Dictionary:
	var frame: Dictionary = _coordination_sources.get(key, {})
	if frame.is_empty(): return {}
	var best: Dictionary = {}
	for item: Dictionary in _coordination_source_pool.get(key, {}).values():
		if item.valid_until <= elapsed: continue
		if best.is_empty() or item.captured_at > best.captured_at or (item.captured_at == best.captured_at and item.valid_until > best.valid_until): best = item
	if best.is_empty(): return {}
	var result := frame.duplicate(true)
	result.merge(best, true)
	return result

## Getter uses board time, makes no new event and never renews a plan. Expired
## short vision can expose a still-valid old clue with its ORIGINAL timestamps.

func coordination_source(context, target_id: int = 0) -> Dictionary:
	var team_id := _coordination_team(context)
	if team_id == 0 or (target_id != 0 and target_id != context.cooperation_target_id()): return {}
	return _active_coordination_source(_coordination_key(team_id, target_id))

func _coordination_source_axis(team_id: int, anchor: Vector3, target_id: int) -> Vector3:
	var center := Vector3.ZERO
	var positions: Array[Vector3] = []
	var ordered: Array = _members.keys()
	ordered.sort()
	for id: int in ordered:
		var context = _context(id)
		if not _reservation_member_valid(context) or _team_by_member.get(id, 0) != team_id: continue
		if target_id != 0 and context.cooperation_target_id() != target_id: continue
		positions.append(context.actor.global_position)
		center += context.actor.global_position
	var direction: Vector3 = center / float(positions.size()) - anchor if not positions.is_empty() else Vector3.ZERO
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		for point: Vector3 in positions:
			direction = point - anchor
			direction.y = 0.0
			if direction.length_squared() >= 0.0001: break
	return direction.normalized() if direction.length_squared() >= 0.0001 else Vector3.FORWARD

func _coordination_clustered(team_id: int, anchor: Vector3, axis: Vector3, target_id: int) -> bool:
	var directions: Array[Vector3] = []
	for id: int in _members:
		var context = _context(id)
		if not _reservation_member_valid(context) or _team_by_member.get(id, 0) != team_id or context.cooperation_target_id() != target_id: continue
		var direction: Vector3 = context.actor.global_position - anchor
		direction.y = 0.0
		if direction.dot(axis) <= FLANK_SIDE_MARGIN: return false
		direction = direction.normalized()
		for previous: Vector3 in directions:
			if previous.dot(direction) <= FLANK_SEPARATION_COSINE: return false
		directions.append(direction)
	return directions.size() >= 2

func _coordination_roles(context, target_id: int) -> Array:
	var result: Array = []
	if not _reservation_member_valid(context) or not context.cooperation_enabled(): return result
	if not context.is_alerted and not context.noise_search_origin.is_finite(): return result
	if target_id != 0 and context.cooperation_target_id() != target_id: return result
	var mobile: bool = context.actor.can_move() and not context.actor.is_vaulting() and not context.actor.melee_active
	if context.coordinated_cooperation_enabled() and mobile and not context.sees_player and context.can_use_action(&"search") and (context.is_alerted or context.noise_search_origin.is_finite()):
		result.append(&"search_sector")
		if target_id != 0:
			result.append(&"inspect_left")
			result.append(&"inspect_right")
	if target_id != 0 and context.coordinated_cooperation_enabled() and has_team_binding(context):
		if context.actor.can_use_firearms() and context.can_use_action(&"reload"): result.append(&"assisted_reload")
		if mobile and context.can_use_action(&"covering_retreat"): result.append(&"assisted_retreat")
	if target_id != 0 and context.can_use_action(&"cooperate"):
		if mobile and coordination_source(context, target_id).get("flank_clustered", false): result.append(&"flank")
		if mobile and context.coordinated_cooperation_enabled() and has_team_binding(context): result.append(&"team_position")
		if context.actor.can_use_firearms() and context.actor.shooting_enabled and not context.actor.is_vaulting() and not context.actor.melee_active:
			result.append(&"front_support")
	return result

## Execution validates one existing role. Enumerating unrelated roles repeatedly
## rechecks team configuration and even queries flank evidence for a fire post.
## Keep these predicates equivalent to the public complete role enumeration;
## nothing is retained across calls, reports, configuration changes or physics.
func _coordination_role_allowed(context, target_id: int, role: StringName) -> bool:
	if not _reservation_member_valid(context) or not context.cooperation_enabled(): return false
	if not context.is_alerted and not context.noise_search_origin.is_finite(): return false
	if target_id != 0 and context.cooperation_target_id() != target_id: return false
	if role in [&"search_sector", &"inspect_left", &"inspect_right"]:
		if role != &"search_sector" and target_id == 0: return false
		return context.coordinated_cooperation_enabled() and context.actor.can_move() and not context.actor.is_vaulting() and not context.actor.melee_active and not context.sees_player and context.can_use_action(&"search")
	if target_id == 0: return false
	if role == &"assisted_reload":
		return context.coordinated_cooperation_enabled() and has_team_binding(context) and context.actor.can_use_firearms() and context.can_use_action(&"reload")
	if role == &"assisted_retreat":
		return context.coordinated_cooperation_enabled() and has_team_binding(context) and context.actor.can_move() and not context.actor.is_vaulting() and not context.actor.melee_active and context.can_use_action(&"covering_retreat")
	if not context.can_use_action(&"cooperate"): return false
	if role == &"front_support":
		return context.actor.can_use_firearms() and context.actor.shooting_enabled and not context.actor.is_vaulting() and not context.actor.melee_active
	if role == &"flank":
		return context.actor.can_move() and not context.actor.is_vaulting() and not context.actor.melee_active and coordination_source(context, target_id).get("flank_clustered", false)
	if role == &"team_position":
		return context.actor.can_move() and not context.actor.is_vaulting() and not context.actor.melee_active and context.coordinated_cooperation_enabled() and has_team_binding(context)
	return false

func _coordination_offer_valid(context, offer: Dictionary, board_time: bool = false) -> bool:
	if not _reservation_member_valid(context) or not _members[context.actor.get_instance_id()].versions_published: return false
	if int(offer.get("team_config_revision", 0)) != team_configuration_revision(context): return false
	if offer.get("scope") != &"tactical": return false
	for key in [&"offer_key", &"owner_action", &"position_set_key", &"role"]:
		if not _reservation_text(offer.get(key)): return false
	if not context.can_use_action(StringName(offer.owner_action)): return false
	var owners: Array = [&"search"] if offer.role in [&"inspect_left", &"inspect_right", &"search_sector"] else [&"cooperate"]
	if has_team_binding(context) and context.coordinated_cooperation_enabled():
		if offer.role == &"front_support": owners.append(&"suppression")
		elif offer.role == &"assisted_reload": owners = [&"reload"]
		elif offer.role == &"assisted_retreat": owners = [&"covering_retreat"]
	if not owners.has(offer.owner_action): return false
	var identity := coordination_identity(context)
	for key in [&"actor_id", &"generation", &"member_generation", &"config_revision", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if typeof(offer.get(key)) != TYPE_INT or offer[key] != identity[key]: return false
	if typeof(offer.get("target_id")) != TYPE_INT or typeof(offer.get("evidence_id")) != TYPE_INT: return false
	if not _coordination_role_allowed(context, offer.target_id, StringName(offer.role)): return false
	var source := coordination_source(context, offer.target_id)
	if source.is_empty() or offer.evidence_id != source.evidence_id: return false
	if not offer.get("position") is Vector3 or not offer.position.is_finite(): return false
	var budget: Array = [2048]
	if not _team_planner._values_only(offer, budget, 0) or not _team_planner._summary_valid(offer.get("path_summary")): return false
	if not _reservation_summary_valid(offer.path_summary): return false
	var summary: Dictionary = offer.path_summary
	if offer.role == &"search_sector" and summary.has("sector_key"):
		if not context.has_method("coordination_search_template_valid") or not context.coordination_search_template_valid(String(summary.sector_key), int(summary.get("source_revision", -1)), int(summary.get("template_navigation_revision", -1))): return false
	if not summary.get("staging_position") is Vector3 or not summary.staging_position.is_finite(): return false
	if not _reservation_number(summary.get("staging_seconds")) or summary.staging_seconds < 0.0: return false
	if not _coordination_frame_valid(summary, source, StringName(offer.role), offer.position, has_team_binding(context) and context.coordinated_cooperation_enabled()): return false
	if offer.role in [&"inspect_left", &"inspect_right", &"search_sector"]:
		var observations: Variant = summary.get("observation_points")
		if not observations is Array or observations.is_empty() or observations.size() > 64: return false
		for point in observations:
			if not point is Vector3 or not point.is_finite(): return false
	for key in [&"cost", &"travel_seconds", &"unavailable_seconds", &"exposed_seconds", &"information_loss", &"measured_support_seconds"]:
		if not _reservation_number(offer.get(key)): return false
		if key != &"cost" and offer[key] < 0.0: return false
	if not offer.get("movement_possible") is bool or not offer.get("fire_ready") is bool: return false
	if offer.role not in [&"front_support", &"assisted_reload"] and not offer.movement_possible: return false
	var now: float = elapsed if board_time else context.evidence_elapsed_seconds
	if offer.has("accept_after"):
		if not _reservation_number(offer.accept_after) or not _reservation_number(offer.get("captured_at")): return false
		if offer.accept_after < offer.captured_at or offer.accept_after > offer.captured_at + COORDINATION_MAX_SECONDS: return false
	return _team_planner._fresh(offer, now)

## Atomic publication: malformed arrays preserve the last legitimate batch.
## An empty legitimate batch withdraws offers, not a running valid assignment.

func submit_offers(context, offers: Array) -> bool:
	if not _reservation_member_valid(context) or offers.size() > 6: return false
	var copied: Array = []
	var keys: Dictionary = {}
	for value in offers:
		if not value is Dictionary or not _coordination_offer_valid(context, value) or keys.has(value.offer_key): return false
		keys[value.offer_key] = true
		var offer: Dictionary = value.duplicate(true)
		offer.path_summary = _coordination_physical_summary(context, value.path_summary, value.target_id)
		var offset: float = elapsed - context.evidence_elapsed_seconds
		offer.captured_at = maxf(0.0, float(offer.captured_at) + offset)
		offer.valid_until = float(offer.valid_until) + offset
		if offer.has("accept_after"): offer.accept_after = float(offer.accept_after) + offset
		copied.append(offer)
	_coordination_offers[context.actor.get_instance_id()] = copied
	# Publication does not invoke the planner or bypass its maintenance period.
	return true

func _coordination_team_members(team_id: int) -> Array:
	var result: Array = []
	for id: int in _members:
		if _team_by_member.get(id, 0) == team_id and _reservation_member_valid(_context(id)) and _members[id].versions_published: result.append(id)
	result.sort()
	return result

func _coordination_environment(team_id: int, ids: Array) -> int:
	var signature: Array = []
	for id: int in ids:
		var member: Dictionary = _members[id]
		signature.append([id, member.member_generation, member.environment_revision, member.navigation_revision])
	var previous: Dictionary = _coordination_environments.get(team_id, {})
	if previous.is_empty() or previous.signature != signature:
		_serial += 1
		_coordination_environments[team_id] = {"signature": signature, "revision": _serial}
	return int(_coordination_environments[team_id].revision)

func _coordination_plan_source(plan: Dictionary) -> Dictionary:
	var source := _active_coordination_source(_coordination_key(plan.team_id, plan.target_id))
	return source if not source.is_empty() and source.valid_until > elapsed and source.evidence_id == plan.evidence_id else {}

func _coordination_assignment_valid(plan: Dictionary, entry: Dictionary) -> bool:
	var context = _context(int(entry.actor_id))
	if _coordination_plan_source(plan).is_empty() or plan.expires_at <= elapsed or entry.expires_at <= elapsed: return false
	if not _reservation_member_valid(context) or _coordination_team(context) != plan.team_id: return false
	if int(entry.get("team_config_revision", 0)) != team_configuration_revision(context): return false
	if not _coordination_role_allowed(context, plan.target_id, StringName(entry.role)) or not context.can_use_action(entry.owner_action): return false
	var identity := coordination_identity(context)
	for key in [&"member_generation", &"config_revision", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if entry[key] != identity[key]: return false
	if entry.get("failed", false): return false
	var primary: Dictionary = environment.reservation_value(entry.reservation_id)
	var pending: Dictionary = environment.reservation_value(entry.get("pending_reservation_id", 0))
	if primary.is_empty() and (pending.is_empty() or pending.accept_until <= elapsed): return false
	if not entry.accepted and entry.accept_until <= elapsed: return false
	return true

## A cheap decision hint only. Acceptance still uses the complete live contract;
## this never grants permission or exposes the internal assignment dictionaries.

func assignment_decision_revision(context) -> int:
	var owner_id: int = context.actor.get_instance_id()
	var plan: Dictionary = _coordination_plans.get(_team_by_member.get(owner_id, 0), {})
	for entry: Dictionary in plan.get("assignments", []):
		if entry.actor_id == owner_id:
			return hash([generation, plan.plan_id, entry.assignment_id, entry.assignment_revision])
	return 0

func _assignment_for_owner(owner_id: int) -> Dictionary:
	var plan: Dictionary = _coordination_plans.get(_team_by_member.get(owner_id, 0), {})
	if plan.is_empty(): return {}
	for entry: Dictionary in plan.assignments:
		if entry.actor_id == owner_id and _coordination_assignment_valid(plan, entry): return entry
	return {}

func _assignment_token(context, token: Dictionary) -> Dictionary:
	if not _reservation_member_valid(context): return {}
	var entry := _assignment_for_owner(context.actor.get_instance_id())
	if entry.is_empty(): return {}
	for key in [&"plan_id", &"plan_version", &"assignment_id", &"assignment_revision", &"actor_id", &"generation", &"team_id", &"evidence_id"]:
		if token.get(key) != entry[key]: return {}
	return entry

## A live plan does not require its original preview offers to remain in cache.

func assignment(context) -> Dictionary:
	if not _reservation_member_valid(context): return {}
	var entry := _assignment_for_owner(context.actor.get_instance_id())
	if entry.is_empty(): return {}
	var plan: Dictionary = _coordination_plans[entry.team_id]
	var result := _assignment_snapshot(entry)
	result.phase = plan.phase
	result.phase_id = plan.phase_id
	result.release_at = plan.release_at
	result.stage_until = plan.stage_until
	result.tactic = plan.tactic
	result.support_links = plan.get("support_links", []).filter(func(link): return link.provider_id == entry.actor_id or link.beneficiary_id == entry.actor_id).duplicate(true)
	return result

## Read actual assigned fire at consumption time. A planned position, a pending
## replacement and an old phase report never authorize a dependent action.

func assignment_support(context) -> Dictionary:
	var result := {"linked": false, "ready": false, "support_seconds": 0.0, "provider_id": 0,
		"cycle_valid": false, "resume_seconds": -1.0, "released": false}
	var entry := _assignment_for_owner(context.actor.get_instance_id())
	if entry.is_empty(): return result
	var plan: Dictionary = _coordination_plans[entry.team_id]
	for link: Dictionary in plan.get("support_links", []):
		if link.beneficiary_id != entry.actor_id or link.expires_at <= elapsed: continue
		result.linked = true
		result.provider_id = link.provider_id
		result.released = plan.phase == &"executing" and plan.release_at >= 0.0 and plan.release_at <= elapsed
		if link.has("pending_provider_id"): return result
		var provider_entry := _assignment_for_owner(link.provider_id)
		var provider = _context(link.provider_id)
		if provider_entry.is_empty() or not provider_entry.accepted or provider_entry.role != &"front_support" or provider_entry.plan_id != plan.plan_id: return result
		var actual := _coordination_actual(provider, plan.target_id)
		var status: Dictionary = _members[link.provider_id].status
		var age: float = elapsed - float(status.get("updated_at", -INF))
		result.ready = actual.fire_ready and not status.get("moving", false)
		result.support_seconds = actual.measured_support_seconds if result.ready else 0.0
		result.cycle_valid = age <= COORDINATION_REPORT_SECONDS and status.get("support_cycle_valid", false) and not status.get("moving", false) and not provider.actor.ammo.is_reloading and provider.actor.ammo.magazine_rounds > 0
		result.resume_seconds = maxf(0.0, float(status.get("support_resume_seconds", 0.0)) - age) if result.cycle_valid else -1.0
		return result
	return result

## Internal previews can be large. Exclude them before copying public values;
## all remaining nested arrays/dictionaries still belong to the caller.

func _assignment_snapshot(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	result.erase("raw_offers")
	return result.duplicate(true)

func _coordination_reservation(context, entry: Dictionary, plan: Dictionary) -> Dictionary:
	var first: Dictionary = entry.reserved_offers[0]
	var reservation := _reservation_footprint(context, first.position)
	reservation.merge(coordination_identity(context))
	reservation.merge({"reservation_id": entry.reservation_id, "assignment_id": entry.assignment_id,
		"owner_id": entry.actor_id, "owner_action": entry.owner_action, "offer_key": first.offer_key,
		"position_set_key": first.position_set_key, "path_summary": _reservation_summary(first.path_summary),
		"scope": &"tactical", "role": entry.role, "target_id": plan.target_id, "evidence_id": plan.evidence_id,
		"phase": &"pending", "created_at": elapsed, "expires_at": entry.expires_at, "accept_until": entry.accept_until,
		"selected_offer_key": "", "alternatives": entry.reserved_offers.duplicate(true)})
	return reservation

func prepare_assignment(context, identity: Dictionary, offer_key: String) -> Dictionary:
	var entry := _assignment_token(context, identity)
	if entry.is_empty() or not entry.allowed_offer_keys.has(offer_key): return {}
	if entry.accepted and not entry.get("segment_boundary", false): return {}
	var selected: Dictionary = {}
	for option: Dictionary in entry.reserved_offers:
		if option.offer_key == offer_key: selected = option
	if selected.is_empty(): return {}
	var existing_pending: Dictionary = environment.reservation_value(entry.get("pending_reservation_id", 0))
	if not existing_pending.is_empty() and existing_pending.offer_key == offer_key and _reservation_valid(existing_pending):
		return existing_pending.duplicate(true) if _reservation_position_available(context, existing_pending, existing_pending.reservation_id) else {}
	var reservation: Dictionary = environment.reservation_value(entry.reservation_id)
	if reservation.is_empty() or not _reservation_valid(reservation): return {}
	var proposed := reservation.duplicate(true)
	proposed.merge({"position": selected.position, "offer_key": selected.offer_key,
		"position_set_key": selected.position_set_key, "path_summary": _reservation_summary(selected.path_summary),
		"selected_offer_key": selected.offer_key}, true)
	if not _reservation_position_available(context, proposed, int(reservation.reservation_id)): return {}
	if entry.accepted:
		# A different allowed segment gets a separate pending physical lease;
		# the task itself and its original deadline remain exactly the same.
		_serial += 1
		proposed.reservation_id = _serial
		proposed.phase = &"pending"
		proposed.created_at = elapsed
		proposed.accept_until = minf(entry.expires_at, elapsed + COORDINATION_ACCEPT_SECONDS)
		proposed.erase("accepted_at")
		if not existing_pending.is_empty(): environment.release_tactical_reservation(self, existing_pending.reservation_id)
		entry.pending_reservation_id = proposed.reservation_id
	environment.store_tactical_reservation(self, proposed)
	return proposed.duplicate(true)

func commit_assignment(context, identity: Dictionary, reservation_token: Dictionary) -> bool:
	var entry := _assignment_token(context, identity)
	if entry.is_empty(): return false
	var expected: int = int(entry.get("pending_reservation_id", entry.reservation_id))
	if expected != reservation_token.get("reservation_id"): return false
	var reservation: Dictionary = environment.reservation_value(expected)
	if reservation.is_empty() or reservation.get("selected_offer_key", "") == "": return false
	if entry.accepted and expected == entry.reservation_id: return validate_reservation(context, reservation_token)
	if not commit_reservation(context, reservation_token): return false
	var initial: bool = not entry.accepted
	entry.accepted = true
	entry.reservation_id = expected
	entry.erase("pending_reservation_id")
	entry.selected_offer_key = reservation.offer_key
	entry.selected_position = reservation.position
	for selected: Dictionary in entry.reserved_offers:
		if selected.offer_key == entry.selected_offer_key:
			entry.staging_position = selected.path_summary.staging_position
			entry.observation_points = selected.path_summary.get("observation_points", []).duplicate()
	if initial: entry.accepted_at = elapsed
	entry.support_prepare_until = minf(entry.expires_at, elapsed + COORDINATION_WAIT_SECONDS)
	entry.last_report_at = elapsed
	entry.ready_for_phase = false
	entry.segment_boundary = false
	return true

func rollback_assignment(context, identity: Dictionary, reservation_token: Dictionary) -> void:
	var entry := _assignment_token(context, identity)
	if entry.is_empty(): return
	var expected: int = int(entry.get("pending_reservation_id", entry.reservation_id))
	if expected != reservation_token.get("reservation_id"): return
	var reservation: Dictionary = _reservation_token(context, reservation_token)
	if reservation.is_empty() or reservation.phase != &"pending": return
	rollback_reservation(context, reservation_token)
	# Canceling preparation before the caller clears the old action leaves its
	# accepted lease intact. A failed begin after clear cannot resurrect it.
	if entry.accepted and expected != entry.reservation_id and environment.has_reservation(entry.reservation_id):
		entry.erase("pending_reservation_id")
		return
	environment.release_tactical_reservation(self, entry.reservation_id)
	entry.erase("pending_reservation_id")
	entry.failed = true
	entry.failure_reason = &"begin_failed"
	_coordination_failures.append({"actor_id": entry.actor_id, "offer_key": reservation_token.offer_key,
		"valid_until": minf(entry.expires_at, elapsed + 2.0), "team_id": entry.team_id,
		"target_id": entry.target_id, "evidence_id": entry.evidence_id})
	if _coordination_failures.size() > 128: _coordination_failures.pop_front()
	_coordination_due[entry.team_id] = elapsed

## Reports describe the action's validated local execution. They cannot change
## geometry, identities, lease durations, Fire state or any other actor's body.

func report_assignment(context, report: Dictionary) -> bool:
	var entry := _assignment_token(context, report)
	if entry.is_empty(): return false
	var plan: Dictionary = _coordination_plans[entry.team_id]
	if report.get("phase_id") != plan.phase_id: return false
	var state: StringName = report.get("state", &"")
	if state not in [&"moving", &"arrived", &"complete", &"unavailable", &"self_preservation"]: return false
	if not entry.accepted and state not in [&"unavailable", &"self_preservation"]: return false
	if not report.get("segment_boundary", false) is bool: return false
	if state in [&"unavailable", &"self_preservation"]:
		entry.failed = true
		entry.failure_reason = state
		environment.release_tactical_reservation(self, entry.reservation_id)
		environment.release_tactical_reservation(self, entry.get("pending_reservation_id", 0))
		_record_coordination_failure(entry, plan)
		_coordination_due[plan.team_id] = elapsed
		return true
	if report.get("execution_valid", true) != true: return false
	if state == &"arrived":
		if context.actor.global_position.distance_to(entry.staging_position) > 0.35 or context.actor.is_vaulting() or context.actor.melee_active: return false
		if entry.role not in [&"front_support", &"assisted_reload"] and not context.actor.can_move(): return false
	if state == &"complete":
		if entry.complete: return true
		if entry.role in [&"flank", &"inspect_left", &"inspect_right"] and context.actor.global_position.distance_to(entry.selected_position) > 0.35: return false
		if plan.phase != &"executing" or plan.release_at < 0.0 or elapsed < plan.release_at: return false
		if entry.role in [&"inspect_left", &"inspect_right", &"search_sector"]:
			if not _record_assignment_observations(context, entry, plan, report): return false
			for expected: Vector3 in entry.observation_points:
				if not entry.get("observed_points", {}).has(expected): return false
		entry.complete = true
	if state != &"complete" and plan.phase == &"executing" and plan.release_at >= 0.0 and elapsed >= plan.release_at:
		if not _record_assignment_observations(context, entry, plan, report): return false
	entry.last_report_at = elapsed
	entry.segment_boundary = report.get("segment_boundary", false)
	entry.position = context.actor.global_position
	entry.ready_for_phase = state == &"arrived"
	entry.report_phase_id = plan.phase_id
	return true


## Incremental observations belong to this accepted assignment and version.
## Re-reporting a point never renews its original observation or expiry.

func _record_assignment_observations(context, entry: Dictionary, plan: Dictionary, report: Dictionary) -> bool:
	if entry.role not in [&"inspect_left", &"inspect_right", &"search_sector"]: return true
	var checked: Variant = report.get("checked_points", PackedVector3Array())
	if not checked is PackedVector3Array or checked.size() > 64: return false
	for point: Vector3 in checked:
		if not point.is_finite() or not entry.observation_points.has(point) or not context.perception.can_observe_position(point): return false
	if not entry.has("observed_points"): entry.observed_points = {}
	var newly_checked := PackedVector3Array()
	for point: Vector3 in checked:
		if entry.observed_points.has(point): continue
		entry.observed_points[point] = elapsed
		newly_checked.append(point)
		var grid := Vector3i(roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0))
		_coordination_checked[[plan.team_id, plan.evidence_id, grid]] = {"position": point, "observer_id": entry.actor_id,
			"team_id": plan.team_id, "target_id": plan.target_id, "evidence_id": plan.evidence_id,
			"navigation_revision": entry.navigation_revision, "observed_at": elapsed, "valid_until": minf(float(_coordination_plan_source(plan).valid_until), elapsed + maxf(0.1, context.setting(&"cooperation", &"checked_point_seconds", 3.0)))}
	if plan.target_id != 0 and not newly_checked.is_empty(): publish_checked(context, newly_checked)
	return true

## Negative observations are kept in the task domain, never the shared map.
## In particular targetless sound never becomes a negative player observation.

func coordination_checked_points(context, target_id: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source := coordination_source(context, target_id)
	if source.is_empty(): return result
	var navigation_version: int = int(coordination_identity(context).get("navigation_revision", -1))
	for checked: Dictionary in _coordination_checked.values():
		if checked.team_id == source.team_id and checked.target_id == target_id and checked.evidence_id == source.evidence_id and checked.valid_until > elapsed and checked.get("navigation_revision", -1) == navigation_version: result.append(checked.duplicate(true))
	return result

func _coordination_occupancy(context) -> Array:
	return environment.coordination_occupancy(context, COORDINATION_PERIOD)

func _coordination_requests(ids: Array, source: Dictionary) -> Array:
	var result: Array = []
	for id: int in ids:
		var context = _context(id)
		var status: Dictionary = _members[id].status
		var age: float = elapsed - float(status.get("updated_at", -INF))
		if age > 0.35 or status.get("target_id", 0) != source.target_id: continue
		if context.actor.ammo.is_reloading and status.get("reloading", false) and status.has("reload_request_id"):
			var remaining: float = maxf(0.0, float(status.get("reload_seconds", 0.0)) - age)
			if remaining > 0.0:
				result.append({"request_id": status.reload_request_id, "actor_id": id, "kind": &"reload", "actual": true,
					"target_id": source.target_id, "evidence_id": source.evidence_id, "captured_at": float(status.updated_at),
					"valid_until": minf(elapsed + remaining, float(status.updated_at) + 0.35)})
		var need: Dictionary = status.get("support_request", {})
		if need.get("kind") == &"retreat" and status.get("moving", false) and status.has("support_request_id"):
			var remaining: float = maxf(0.0, float(need.get("duration", 0.0)) - age)
			if remaining > 0.0:
				result.append({"request_id": status.support_request_id, "actor_id": id, "kind": &"retreat", "actual": true,
					"target_id": source.target_id, "evidence_id": source.evidence_id, "captured_at": float(status.updated_at),
					"valid_until": minf(elapsed + remaining, float(status.updated_at) + 0.35)})
	var plan: Dictionary = _coordination_plans.get(source.team_id, {})
	if not plan.is_empty():
		for entry: Dictionary in plan.assignments:
			if not entry.accepted or entry.complete or not entry.role in [&"flank", &"team_position", &"assisted_reload", &"assisted_retreat", &"inspect_left", &"inspect_right", &"search_sector"] or not _coordination_assignment_valid(plan, entry): continue
			var status: Dictionary = _members[entry.actor_id].status
			var moving: bool = elapsed - float(status.get("updated_at", -INF)) <= 0.35 and status.get("moving", false)
			var kind: StringName = &"reload" if entry.role == &"assisted_reload" else (&"retreat" if entry.role == &"assisted_retreat" else &"advance")
			var actual: bool = status.get("reloading", false) if kind == &"reload" else moving
			if not actual and elapsed > float(entry.get("support_prepare_until", -INF)): continue
			result.append({"request_id": entry.assignment_id, "assignment_id": entry.assignment_id, "actor_id": entry.actor_id, "kind": kind, "accepted": true, "actual": actual,
				"target_id": source.target_id, "evidence_id": source.evidence_id, "captured_at": entry.accepted_at,
				"valid_until": entry.expires_at if actual else minf(entry.expires_at, float(entry.get("support_prepare_until", entry.expires_at)))})
	return result.slice(0, 32)

func _coordination_frame_valid(summary: Dictionary, source: Dictionary, role: StringName, position: Vector3, support_any_side: bool = false) -> bool:
	if role not in [&"flank", &"front_support"] or not summary.has("tactical_key"): return true
	var anchor: Variant = summary.get("tactical_anchor")
	var axis: Variant = summary.get("tactical_axis")
	if not anchor is Vector3 or not axis is Vector3 or not anchor.is_finite() or not axis.is_finite(): return false
	if anchor.distance_to(source.position) > 0.001 or axis.distance_to(source.front_axis) > 0.001 or absf(axis.y) > 0.001 or absf(axis.length() - 1.0) > 0.001: return false
	var side: float = (position - anchor).dot(axis)
	if role == &"front_support" and support_any_side:
		return summary.get("side", 0) == (1 if side > FLANK_SIDE_MARGIN else (-1 if side < -FLANK_SIDE_MARGIN else 0))
	return side < -FLANK_SIDE_MARGIN if role == &"flank" else side > FLANK_SIDE_MARGIN

func _coordination_offer_observed(source: Dictionary, offer: Dictionary) -> bool:
	if _coordination_checked.is_empty() or offer.role not in [&"inspect_left", &"inspect_right", &"search_sector"]: return false
	for point: Vector3 in offer.path_summary.observation_points:
		var grid := Vector3i(roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0))
		var checked: Dictionary = _coordination_checked.get([source.team_id, source.evidence_id, grid], {})
		if checked.is_empty() or checked.valid_until <= elapsed or checked.target_id != source.target_id or checked.get("navigation_revision", -1) != offer.navigation_revision: return false
	return true

func publish_personal_baseline(context, summary: Dictionary) -> void:
	if not _reservation_member_valid(context): return
	var id: int = context.actor.get_instance_id()
	if summary.is_empty():
		_coordination_baselines.erase(id)
		return
	for key in [&"cost", &"horizon", &"unavailable_seconds", &"exposed_seconds", &"information_loss"]:
		if not _reservation_number(summary.get(key)): return
	if summary.horizon <= 0.0: return
	var value := summary.duplicate(true)
	value.captured_at = elapsed
	value.valid_until = elapsed + 1.5
	_coordination_baselines[id] = value

func _coordination_snapshot(team_id: int, source: Dictionary, ids: Array) -> Dictionary:
	var environment := _coordination_environment(team_id, ids)
	var current: Dictionary = _coordination_plans.get(team_id, {})
	var frame: Dictionary = current.get("tactical_frame", {}) if not current.is_empty() else {"anchor": source.position, "axis": source.front_axis}
	var members: Array = []
	var representative = _context(ids[0])
	for id: int in ids:
		var context = _context(id)
		var identity := coordination_identity(context)
		var actual := _coordination_actual(context, source.target_id)
		var offers: Array = []
		for raw: Dictionary in _coordination_offers.get(id, []):
			if raw.target_id != source.target_id or raw.evidence_id != source.evidence_id or not _coordination_offer_valid(context, raw, true): continue
			if _coordination_offer_observed(source, raw): continue
			var normalized := raw.duplicate(true)
			normalized.path_summary = _coordination_physical_summary(context, raw.path_summary, source.target_id)
			# Original per-member versions remain in raw_offers for acceptance.
			normalized.environment_revision = environment
			if normalized.role == &"front_support":
				normalized.fire_ready = actual.fire_ready and raw.fire_ready
				normalized.measured_support_seconds = minf(raw.measured_support_seconds, actual.measured_support_seconds)
				if raw.path_summary.get("holds_front", false) and _members[id].status.get("moving", false): normalized.fire_ready = false
			offers.append(normalized)
		var far: bool = context.cooperation_target_id() == source.target_id and not frame.is_empty() and (context.actor.global_position - frame.anchor).dot(frame.axis) < -FLANK_SIDE_MARGIN
		var status: Dictionary = _members[id].status
		members.append({"actor_id": id, "member_generation": identity.member_generation, "config_revision": identity.config_revision,
			"navigation_revision": identity.navigation_revision, "position": context.actor.global_position,
			"advanced_enabled": context.cooperation_enabled(), "eligible_roles": _coordination_roles(context, source.target_id),
			"offers": offers, "actual_support": actual, "on_far_side": far,
			"advisory_active": _recommendations.get(id, {}).get("accepted", false),
			"personal_baseline": _coordination_baselines.get(id, {}).duplicate(true),
			"status": {"rounds": int(status.get("rounds", 0)), "magazine_capacity": int(status.get("magazine_capacity", 0)),
				"needs_fire_handoff": float(status.get("rounds", 0)) / maxf(1.0, float(status.get("magazine_capacity", 0))) <= float(context.setting(&"cooperation", &"reload_rounds_ratio", 0.35)),
				"health_ratio": float(status.get("health_ratio", 1.0)), "pressure": float(status.get("pressure", 0.0)),
				"reloading": bool(status.get("reloading", false)), "can_move": context.actor.can_move()}})
	var snapshot_value := {"now": elapsed, "generation": generation, "team_id": team_id, "domain": "team:%s" % team_id,
		"target_id": source.target_id, "evidence_id": source.evidence_id, "environment_revision": environment,
		"navigation_revision": int(_members[ids[0]].navigation_revision), "relation_revision": relation_revision,
		"members": members, "occupancy": _coordination_occupancy(representative), "requests": _coordination_requests(ids, source),
		"failures": _coordination_failures.filter(func(entry): return entry.team_id == team_id and entry.target_id == source.target_id and entry.evidence_id == source.evidence_id).duplicate(true), "flank_owner_ids": [], "current_plan": {}}
	if has_team_binding(representative):
		snapshot_value.cooperation_level = team_level(representative)
		snapshot_value.team_config_revision = team_configuration_revision(representative)
	for id: int in ids:
		if _recommendations.get(id, {}).get("accepted", false): snapshot_value.flank_owner_ids.append(id)
	if not current.is_empty():
		var projected := current.duplicate()
		projected.erase("assignments")
		projected = projected.duplicate(true)
		projected.assignments = []
		projected.execution_valid = _coordination_plan_source(current).size() > 0 and current.expires_at > elapsed
		projected.segment_boundary = true
		for stored: Dictionary in current.assignments:
			var entry := _assignment_snapshot(stored)
			entry.execution_valid = _coordination_assignment_valid(current, entry)
			var owner = _context(int(entry.actor_id))
			if _reservation_member_valid(owner):
				for reserved: Dictionary in entry.reserved_offers:
					reserved.path_summary = _coordination_physical_summary(owner, reserved.path_summary, current.target_id)
			projected.segment_boundary = projected.segment_boundary and entry.get("segment_boundary", true)
			if entry.role == &"flank" and entry.execution_valid: snapshot_value.flank_owner_ids.append(entry.actor_id)
			projected.assignments.append(entry)
		snapshot_value.current_plan = projected
	return snapshot_value

func _coordination_find_source(team_id: int, ids: Array) -> Dictionary:
	var current: Dictionary = _coordination_plans.get(team_id, {})
	if not current.is_empty(): return _coordination_plan_source(current)
	var best: Dictionary = {}
	for key: String in _coordination_sources:
		if _coordination_sources[key].team_id != team_id: continue
		var source := _active_coordination_source(key)
		if source.is_empty() or (not best.is_empty() and source.captured_at <= best.captured_at): continue
		var offered := false
		for id: int in ids:
			for offer: Dictionary in _coordination_offers.get(id, []):
				if offer.target_id == source.target_id and offer.evidence_id == source.evidence_id and _coordination_offer_valid(_context(id), offer, true):
					offered = true
					break
			if offered: break
		if offered: best = source
	return best

func _coordination_entry(proposal: Dictionary, plan: Dictionary) -> Dictionary:
	var context = _context(int(proposal.actor_id))
	if not _reservation_member_valid(context): return {}
	var raw_offers: Array = []
	for key in proposal.allowed_offer_keys:
		var found := false
		for raw: Dictionary in _coordination_offers.get(proposal.actor_id, []):
			if raw.offer_key == key and _coordination_offer_valid(context, raw, true):
				raw_offers.append(raw.duplicate(true))
				found = true
				break
		if not found: return {}
	if raw_offers.is_empty(): return {}
	var entry := proposal.duplicate(true)
	entry.merge(coordination_identity(context))
	_serial += 1
	entry.assignment_id = _serial
	_serial += 1
	entry.reservation_id = _serial
	entry.assignment_revision = 1
	entry.plan_id = plan.plan_id
	entry.plan_version = plan.plan_version
	entry.target_id = plan.target_id
	entry.evidence_id = plan.evidence_id
	entry.created_at = elapsed
	entry.expires_at = plan.expires_at
	entry.accept_until = minf(plan.expires_at, elapsed + COORDINATION_ACCEPT_SECONDS)
	for raw: Dictionary in raw_offers:
		entry.accept_until = minf(plan.expires_at, maxf(entry.accept_until, float(raw.get("accept_after", elapsed))))
	# Preview expiry gates issuance above. Once assigned, acceptance has its own
	# original fixed window and live body/route validation; it is never renewed.
	entry.accepted = false
	entry.complete = false
	entry.failed = false
	entry.ready_for_phase = false
	entry.segment_boundary = true
	entry.last_report_at = elapsed
	entry.raw_offers = raw_offers
	return entry

func _coordination_plan_duration(proposal: Dictionary) -> float:
	var travel := 0.0
	for entry: Dictionary in proposal.assignments:
		for raw: Dictionary in _coordination_offers.get(entry.actor_id, []):
			if entry.allowed_offer_keys.has(raw.offer_key): travel = maxf(travel, maxf(0.0, float(raw.get("accept_after", elapsed)) - elapsed) + float(raw.travel_seconds))
	return minf(COORDINATION_MAX_SECONDS, maxf(4.0, travel + COORDINATION_WAIT_SECONDS + 2.0))

func _install_coordination_proposal(team_id: int, source: Dictionary, proposal: Dictionary) -> void:
	var previous: Dictionary = _coordination_plans.get(team_id, {})
	if proposal.operation == &"keep": return
	if proposal.operation == &"handoff" and not previous.is_empty():
		_install_support_handoff(previous, proposal)
		return
	if proposal.operation == &"none":
		if not previous.is_empty(): _drop_coordination_plan(team_id, StringName(proposal.reason))
		return
	var extending: bool = proposal.operation == &"extend" and not previous.is_empty()
	var repairing: bool = proposal.operation in [&"repair", &"extend"] and not previous.is_empty()
	var plan: Dictionary = previous.duplicate(true) if repairing else {}
	if not repairing:
		_serial += 1
		plan = {"plan_id": _serial, "plan_version": 1, "generation": generation, "team_id": team_id,
			"domain": "team:%s" % team_id, "target_id": source.target_id, "evidence_id": source.evidence_id,
			"tactic": proposal.tactic, "phase": &"assigning", "phase_id": 1, "release_at": -1.0,
			"created_at": elapsed, "expires_at": minf(source.valid_until, elapsed + _coordination_plan_duration(proposal)),
			"stage_until": elapsed + COORDINATION_ACCEPT_SECONDS, "assignments": [], "tactical_frame": {}}
		plan.posture = proposal.get("posture", &"hold")
		plan.decision = proposal.get("decision", {}).duplicate(true)
		plan.team_config_revision = team_configuration_revision(_context(_coordination_team_members(team_id)[0]))
		plan.stage_until = minf(plan.stage_until, plan.expires_at)
	elif not extending:
		# Repair never extends the original overall deadline or unaffected leases.
		plan.phase = &"assigning"
		plan.phase_id += 1
		plan.release_at = -1.0
		plan.stage_until = minf(plan.expires_at, elapsed + COORDINATION_ACCEPT_SECONDS)
	plan.required_participants = proposal.required_participants.duplicate()
	if proposal.has("request_id"): plan.request_id = proposal.request_id
	var replaced: Dictionary = {}
	if repairing:
		for id: int in proposal.get("removed_actor_ids", []): replaced[id] = 0
	var new_entries: Array = []
	for item: Dictionary in proposal.assignments:
		var entry := _coordination_entry(item, plan)
		if entry.is_empty(): return
		new_entries.append(entry)
		plan.stage_until = minf(plan.expires_at, maxf(plan.stage_until, entry.accept_until))
		if repairing and not extending: replaced[int(item.previous_actor_id)] = int(item.actor_id)
		if item.role == &"flank":
			var summary: Dictionary = entry.raw_offers[0].path_summary
			plan.tactical_frame = {"anchor": summary.tactical_anchor, "axis": summary.tactical_axis, "key": summary.tactical_key}
	var retained: Array = []
	if repairing:
		for entry: Dictionary in plan.assignments:
			if replaced.has(entry.actor_id): continue
			# Retained assignment identity, accepted lease and deadline are unchanged.
			if extending: entry.partner_ids = entry.partner_ids.filter(func(id): return not replaced.has(id))
			else:
				for index in entry.partner_ids.size():
					entry.partner_ids[index] = replaced.get(entry.partner_ids[index], entry.partner_ids[index])
				entry.partner_ids = entry.partner_ids.filter(func(id): return id != 0)
			if not extending:
				entry.ready_for_phase = false
				# A retained flank has already paid for its completed route segments.
				# Freeze this repair phase's entry at its actual current body instead
				# of asking it to return to the original pre-maneuver starting point.
				if entry.role == &"flank" and entry.accepted and not entry.complete:
					entry.staging_position = _context(entry.actor_id).actor.global_position
			retained.append(entry)
	plan.assignments = retained + new_entries
	if not repairing:
		plan.support_links = proposal.get("support_links", []).duplicate(true)
		for link: Dictionary in plan.support_links:
			link.expires_at = plan.expires_at
			link.revision = 1
			for entry: Dictionary in plan.assignments:
				if entry.actor_id == link.beneficiary_id and link.request_id == 0: link.request_id = entry.assignment_id
	elif not extending:
		plan.support_links = plan.get("support_links", []).filter(func(link): return replaced.get(link.get("pending_provider_id", link.provider_id), -1) != 0 and replaced.get(link.beneficiary_id, -1) != 0)
		for link: Dictionary in plan.get("support_links", []):
			var previous_provider: int = link.get("pending_provider_id", link.provider_id)
			if replaced.has(previous_provider): link.pending_provider_id = replaced[previous_provider]
			link.beneficiary_id = replaced.get(link.beneficiary_id, link.beneficiary_id)
			link.revision += 1
			for entry: Dictionary in new_entries:
				if entry.actor_id == link.beneficiary_id and link.kind != &"support": link.request_id = entry.assignment_id
	# Atomic install: every selected preview was validated above. The planner
	# has checked mutual conflicts; transactions recheck current physical facts.
	if not previous.is_empty():
		for old: Dictionary in previous.assignments:
			if not repairing or replaced.has(old.actor_id):
				environment.release_tactical_reservation(self, old.reservation_id)
				environment.release_tactical_reservation(self, old.get("pending_reservation_id", 0))
	_coordination_plans[team_id] = plan
	for entry: Dictionary in new_entries:
		environment.store_tactical_reservation(self, _coordination_reservation(_context(entry.actor_id), entry, plan))
	revision += 1

func _drop_coordination_plan(team_id: int, _reason: StringName) -> void:
	var plan: Dictionary = _coordination_plans.get(team_id, {})
	if plan.is_empty(): return
	for entry: Dictionary in plan.assignments:
		environment.release_tactical_reservation(self, entry.reservation_id)
		environment.release_tactical_reservation(self, entry.get("pending_reservation_id", 0))
	_coordination_plans.erase(team_id)
	revision += 1

func _invalidate_coordination_member(owner_id: int, reason: StringName) -> void:
	var plan: Dictionary = _coordination_plans.get(_team_by_member.get(owner_id, 0), {})
	if plan.is_empty(): return
	for entry: Dictionary in plan.assignments:
		if entry.actor_id == owner_id:
			entry.failed = true
			entry.failure_reason = reason
	_coordination_due[plan.team_id] = elapsed

## Failure cooldown is independent of the abandoned plan's expiry. Rebuilding
## a plan or receiving the same location again cannot erase an actual failure.

func _record_coordination_failure(entry: Dictionary, plan: Dictionary) -> void:
	for failure: Dictionary in _coordination_failures:
		if failure.actor_id == entry.actor_id and failure.position_set_key == entry.reserved_position_sets[0] and failure.team_id == plan.team_id and failure.evidence_id == plan.evidence_id and failure.valid_until > elapsed: return
	_coordination_failures.append({"actor_id": entry.actor_id, "position_set_key": entry.reserved_position_sets[0],
		"valid_until": elapsed + 2.0, "team_id": plan.team_id, "target_id": plan.target_id, "evidence_id": plan.evidence_id})
	if _coordination_failures.size() > 128: _coordination_failures.pop_front()

func _install_support_handoff(plan: Dictionary, proposal: Dictionary) -> void:
	if not plan.get("handoff", {}).is_empty() or proposal.assignments.size() != 1: return
	var entry := _coordination_entry(proposal.assignments[0], plan)
	if entry.is_empty(): return
	var handoff: Dictionary = proposal.handoff.duplicate(true)
	var travel := 0.0
	for offer: Dictionary in entry.raw_offers: travel = maxf(travel, float(offer.travel_seconds))
	handoff.expires_at = minf(plan.expires_at, elapsed + travel + COORDINATION_WAIT_SECONDS)
	plan.handoff = handoff
	plan.assignments.append(entry)
	environment.store_tactical_reservation(self, _coordination_reservation(_context(entry.actor_id), entry, plan))
	revision += 1

func _support_assignment_ready(entry: Dictionary, plan: Dictionary) -> bool:
	if entry.is_empty() or not entry.accepted or entry.get("report_phase_id", -1) != plan.phase_id or elapsed - float(entry.last_report_at) > COORDINATION_REPORT_SECONDS: return false
	var provider = _context(entry.actor_id)
	return provider != null and provider.actor.global_position.distance_to(entry.get("staging_position", Vector3.INF)) <= 0.35 and _coordination_actual(provider, plan.target_id).fire_ready and not _members[entry.actor_id].status.get("moving", false)

func _advance_support_handoff(plan: Dictionary) -> bool:
	# Repair replaces a failed slot, not the last established covering fire.
	# Keep that identity unavailable until its replacement really reaches/fire.
	for link: Dictionary in plan.get("support_links", []):
		if link.has("pending_provider_id") and _support_assignment_ready(_assignment_for_owner(link.pending_provider_id), plan):
			link.provider_id = link.pending_provider_id
			link.erase("pending_provider_id")
			link.revision += 1
			revision += 1
	var handoff: Dictionary = plan.get("handoff", {})
	if not handoff.is_empty():
		var replacement := _assignment_for_owner(handoff.replacement_provider_id)
		var available := _support_assignment_ready(replacement, plan)
		if available:
			for link: Dictionary in plan.get("support_links", []):
				if link.provider_id == handoff.previous_provider_id:
					link.provider_id = handoff.replacement_provider_id
					link.revision += 1
			_remove_support_assignment(plan, handoff.previous_provider_id)
			plan.required_participants = plan.required_participants.map(func(id): return handoff.replacement_provider_id if id == handoff.previous_provider_id else id)
			plan.handoff = {}
			plan.handoff_wait = {}
			revision += 1
		elif replacement.is_empty() or handoff.expires_at <= elapsed:
			_remove_support_assignment(plan, handoff.replacement_provider_id)
			plan.handoff = {}
			# Keep the old dependency only until its original bounded recovery.
			plan.handoff_wait = {"provider_id": handoff.previous_provider_id, "until": elapsed}
	var waiting: Dictionary = plan.get("handoff_wait", {})
	if waiting.is_empty():
		for link: Dictionary in plan.get("support_links", []):
			if link.has("pending_provider_id"): continue
			var provider = _context(link.provider_id)
			if provider == null or not provider.actor.can_use_firearms(): continue
			var ratio: float = float(provider.actor.ammo.magazine_rounds) / maxf(1.0, provider.actor.weapon.magazine_capacity)
			if ratio <= float(provider.setting(&"cooperation", &"reload_rounds_ratio", 0.35)):
				plan.handoff_wait = {"provider_id": link.provider_id, "until": minf(plan.expires_at, elapsed + COORDINATION_WAIT_SECONDS)}
				break
	elif waiting.until <= elapsed and plan.get("handoff", {}).is_empty():
		_drop_coordination_plan(plan.team_id, &"support_handoff_unavailable")
		return false
	return true

func _remove_support_assignment(plan: Dictionary, owner_id: int) -> void:
	for entry: Dictionary in plan.assignments:
		if entry.actor_id == owner_id:
			environment.release_tactical_reservation(self, entry.reservation_id)
			environment.release_tactical_reservation(self, entry.get("pending_reservation_id", 0))
	plan.assignments = plan.assignments.filter(func(entry): return entry.actor_id != owner_id)
	for entry: Dictionary in plan.assignments: entry.partner_ids = entry.partner_ids.filter(func(id): return id != owner_id)

func _advance_coordination_phase(plan: Dictionary) -> void:
	if plan.expires_at <= elapsed or _coordination_plan_source(plan).is_empty():
		for entry: Dictionary in plan.assignments:
			if not entry.complete: _record_coordination_failure(entry, plan)
		_drop_coordination_plan(plan.team_id, &"expired")
		return
	if not _advance_support_handoff(plan): return
	var all_accepted := true
	var all_complete := true
	var movers_complete := true
	var mover_count := 0
	var required_ready := true
	var unready: Array = []
	for entry: Dictionary in plan.assignments:
		if not _coordination_assignment_valid(plan, entry):
			if not entry.failed:
				_record_coordination_failure(entry, plan)
				entry.failed = true
				_coordination_due[plan.team_id] = elapsed
			return
		all_accepted = all_accepted and entry.accepted
		all_complete = all_complete and entry.complete
		if entry.role != &"front_support":
			mover_count += 1
			movers_complete = movers_complete and entry.complete
		if plan.required_participants.has(entry.actor_id) and not entry.complete:
			var context = _context(entry.actor_id)
			var ready: bool = entry.accepted and entry.get("ready_for_phase", false) and entry.get("report_phase_id", -1) == plan.phase_id and elapsed - float(entry.last_report_at) <= COORDINATION_REPORT_SECONDS and context.actor.global_position.distance_to(entry.get("staging_position", Vector3.INF)) <= 0.35
			if entry.role == &"front_support": ready = ready and _coordination_actual(context, plan.target_id).fire_ready
			required_ready = required_ready and ready
			if not ready: unready.append(entry)
	# Front fire supports the actual maneuver; it need not invent a separate
	# completion movement or wait until the whole lease expires after arrival.
	if all_complete or (plan.tactic in [&"flank", &"concentrate", &"disperse", &"reload", &"retreat"] and mover_count > 0 and movers_complete):
		_drop_coordination_plan(plan.team_id, &"complete")
		return
	if plan.phase == &"assigning" and all_accepted:
		plan.phase = &"staging"
		plan.phase_id += 1
		var longest := 0.0
		for entry: Dictionary in plan.assignments:
			for offer: Dictionary in entry.raw_offers: longest = maxf(longest, float(offer.path_summary.staging_seconds))
		plan.stage_until = minf(plan.expires_at, elapsed + longest + COORDINATION_WAIT_SECONDS)
		for entry: Dictionary in plan.assignments: entry.support_prepare_until = minf(entry.expires_at, plan.stage_until)
		# Non-synchronized support/search tasks start after acceptance; inspect
		# and flank wait on real same-phase entry facts, never preview ready.
		if plan.required_participants.is_empty(): required_ready = true
		else: required_ready = false
	if plan.phase == &"staging" and required_ready:
		plan.phase = &"executing"
		plan.phase_id += 1
		plan.release_at = elapsed
		for entry: Dictionary in plan.assignments:
			entry.support_prepare_until = minf(entry.expires_at, elapsed + COORDINATION_WAIT_SECONDS)
		plan.stage_until = plan.expires_at
		revision += 1
	elif plan.phase != &"executing" and elapsed >= plan.stage_until:
		for entry: Dictionary in unready: _record_coordination_failure(entry, plan)
		# A late additional flank has exhausted its own preparation window. Keep
		# the already-ready front/flank pair and feed the failed slot to ordinary
		# bounded repair; never renew this slot or the whole plan's fixed lease.
		var repairable: bool = plan.phase == &"staging" and plan.tactic == &"flank" and not unready.is_empty() and unready.all(func(entry): return entry.role == &"flank")
		repairable = repairable and plan.assignments.any(func(entry): return entry.role == &"front_support" and not unready.has(entry))
		repairable = repairable and plan.assignments.any(func(entry): return entry.role == &"flank" and not unready.has(entry) and not entry.complete)
		if repairable:
			for entry: Dictionary in unready: entry.failed = true
			_coordination_due[plan.team_id] = elapsed
			return
		_drop_coordination_plan(plan.team_id, &"stage_timeout")

func _advance_coordination() -> void:
	if _coordination_sources.is_empty() and _coordination_plans.is_empty(): return
	for key in _coordination_checked.keys():
		if _coordination_checked[key].valid_until <= elapsed: _coordination_checked.erase(key)
	for index in range(_coordination_failures.size() - 1, -1, -1):
		if _coordination_failures[index].valid_until <= elapsed: _coordination_failures.remove_at(index)
	var active: Dictionary = {}
	for team: Dictionary in _teams.values(): active[team.team_id] = true
	for team_id in _coordination_plans.keys():
		if not active.has(team_id): _drop_coordination_plan(team_id, &"team_changed")
		else: _advance_coordination_phase(_coordination_plans[team_id])
	for key in _coordination_sources.keys():
		if not active.has(_coordination_sources[key].team_id) or _active_coordination_source(key).is_empty():
			_coordination_sources.erase(key)
			_coordination_source_pool.erase(key)
	for registry: Dictionary in [_coordination_environments, _coordination_due, _coordination_counters]:
		for team_id in registry.keys():
			if not active.has(team_id): registry.erase(team_id)
	for key in _coordination_receipts.keys():
		if not _members.has(int(key[0])): _coordination_receipts.erase(key)
	for team_id: int in active:
		if elapsed < float(_coordination_due.get(team_id, 0.0)): continue
		_coordination_due[team_id] = elapsed + COORDINATION_PERIOD
		var ids := _coordination_team_members(team_id)
		if ids.size() < 2 or ids.size() > 32:
			_drop_coordination_plan(team_id, &"unsupported_team_size")
			continue
		var source := _coordination_find_source(team_id, ids)
		if source.is_empty(): continue
		var snapshot_value := _coordination_snapshot(team_id, source, ids)
		var proposal: Dictionary = _team_planner.propose(snapshot_value)
		planning_count += 1
		_coordination_counters[team_id] = proposal.get("counters", {}).duplicate(true)
		if proposal.operation == &"recommend":
			_drop_coordination_plan(team_id, &"advisory_mode")
			_install_recommendations(team_id, source, proposal)
		else: _install_coordination_proposal(team_id, source, proposal)

func _recommendation_valid(context, entry: Dictionary) -> bool:
	if entry.is_empty() or not _reservation_member_valid(context) or context.cooperation_level() != 1 or not context.cooperation_enabled(): return false
	if entry.expires_at <= elapsed or (not entry.accepted and entry.accept_until <= elapsed): return false
	var identity := coordination_identity(context)
	for key in [&"generation", &"member_generation", &"team_id", &"config_revision", &"team_config_revision", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if entry.get(key) != identity.get(key): return false
	var source := _active_coordination_source(_coordination_key(entry.team_id, entry.target_id))
	return not source.is_empty() and source.evidence_id == entry.evidence_id and entry.target_id == context.cooperation_target_id()

func recommendation(context) -> Dictionary:
	var entry: Dictionary = _recommendations.get(context.actor.get_instance_id(), {})
	return entry.duplicate(true) if _recommendation_valid(context, entry) else {}

func recommendation_available(context, identity: Dictionary, offer_key: String) -> bool:
	var entry: Dictionary = _recommendations.get(context.actor.get_instance_id(), {})
	if not _recommendation_valid(context, entry) or entry.recommendation_id != identity.get("recommendation_id") or not entry.allowed_offer_keys.has(offer_key): return false
	if entry.accepted: return true
	var summary: Dictionary = entry.reserved_offers[0].path_summary
	var anchor: Vector3 = summary.tactical_anchor
	var axis: Vector3 = summary.tactical_axis
	var eligible := 0
	var owners: Dictionary = {context.actor.get_instance_id(): true}
	var front := false
	for id: int in _coordination_team_members(entry.team_id):
		var other = _context(id)
		if not other.cooperation_enabled(): continue
		eligible += 1
		if (other.actor.global_position - anchor).dot(axis) < -FLANK_SIDE_MARGIN or _recommendations.get(id, {}).get("accepted", false): owners[id] = true
		elif id != context.actor.get_instance_id() and (other.actor.global_position - anchor).dot(axis) > FLANK_SIDE_MARGIN: front = true
	return front and owners.size() <= floori(float(eligible) / 2.0)

func prepare_recommendation(context, advice: Dictionary, key: String, offer: Dictionary, duration: float) -> Dictionary:
	if not recommendation_available(context, advice, key): return {}
	var token := prepare_reservation(context, offer, duration)
	if token.is_empty(): return {}
	return environment.attach_recommendation(context, int(token.reservation_id), int(advice.recommendation_id), float(_recommendations[context.actor.get_instance_id()].expires_at))

func accept_recommendation(context, advice: Dictionary, token: Dictionary) -> bool:
	var entry: Dictionary = _recommendations.get(context.actor.get_instance_id(), {})
	if not _recommendation_valid(context, entry) or entry.recommendation_id != advice.get("recommendation_id") or token.get("recommendation_id") != entry.recommendation_id: return false
	# Preparing only reserves space. Another recommendation may acquire the
	# last flank slot before this transaction commits its selected action.
	if not recommendation_available(context, advice, entry.allowed_offer_keys[0]): return false
	if not commit_reservation(context, token): return false
	entry.accepted = true
	return true

func _maintain_recommendations() -> void:
	for id: int in _recommendations.keys():
		var entry: Dictionary = _recommendations[id]
		if _recommendation_valid(_context(id), entry): continue
		_recommendation_cooldowns[id] = elapsed + COORDINATION_PERIOD
		_recommendations.erase(id)
	for id in _recommendation_cooldowns.keys():
		if not _members.has(id) or _recommendation_cooldowns[id] <= elapsed: _recommendation_cooldowns.erase(id)

func _install_recommendations(team_id: int, source: Dictionary, proposal: Dictionary) -> void:
	for item: Dictionary in proposal.get("recommendations", []):
		var context = _context(item.actor_id)
		if _recommendations.has(item.actor_id) or _recommendation_cooldowns.has(item.actor_id) or not _reservation_member_valid(context): continue
		var entry := item.duplicate(true)
		entry.merge(coordination_identity(context))
		_serial += 1
		entry.merge({"recommendation_id": _serial, "team_id": team_id, "target_id": source.target_id, "evidence_id": source.evidence_id,
			"created_at": elapsed, "accept_until": elapsed + COORDINATION_ACCEPT_SECONDS,
			"expires_at": minf(source.valid_until, elapsed + maxf(4.0, float(context.setting(&"cooperation", &"flank_plan_seconds", 14.0)))), "accepted": false})
		_recommendations[item.actor_id] = entry

func _context(id: int):
	return _members[id].context.get_ref() if _members.has(id) else null

func _coordination_actual(context, target_id: int) -> Dictionary:
	return environment._coordination_actual(context, target_id)

func _coordination_physical_summary(context, summary: Dictionary, target_id: int) -> Dictionary:
	return environment._coordination_physical_summary(context, summary, target_id)

func _domain(actor) -> String:
	return environment._domain(actor)

func _inspection_domain_matches(context, report: Dictionary) -> bool:
	return environment._inspection_domain_matches(context, report)

func _reservation_footprint(context, position: Vector3) -> Dictionary:
	return environment._reservation_footprint(context, position)

func _reservation_geometry_conflict(first: Dictionary, second: Dictionary) -> bool:
	return environment._reservation_geometry_conflict(first, second)

func _reservation_member_valid(context) -> bool:
	return context != null and is_instance_valid(context.actor) and _members.has(context.actor.get_instance_id()) and environment._reservation_member_valid(context)

func _reservation_number(value: Variant) -> bool:
	return environment._reservation_number(value)

func _reservation_position_available(context, entry: Dictionary, except_id: int = 0) -> bool:
	return environment._reservation_position_available(context, entry, except_id)

func _reservation_projections(entry: Dictionary) -> Array:
	return environment._reservation_projections(entry)

func _reservation_summary(summary: Dictionary) -> Dictionary:
	return environment._reservation_summary(summary)

func _reservation_summary_valid(summary: Variant) -> bool:
	return environment._reservation_summary_valid(summary)

func _reservation_text(value: Variant) -> bool:
	return environment._reservation_text(value)

func _reservation_token(context, token: Dictionary) -> Dictionary:
	return environment._reservation_token(context, token)

func _reservation_valid(entry: Dictionary) -> bool:
	return environment._reservation_valid(entry)

func can_cooperate(first_id: int, second_id: int) -> bool:
	return environment.can_cooperate(first_id, second_id)

func can_share_intel(sender_id: int, receiver_id: int) -> bool:
	return environment.can_share_intel(sender_id, receiver_id)

func can_share_space(first_id: int, second_id: int) -> bool:
	return environment.can_share_space(first_id, second_id)

func commit_reservation(context, token: Dictionary) -> bool:
	return environment.commit_reservation(context, token)

func coordination_identity(context) -> Dictionary:
	return environment.coordination_identity(context)

func has_team_binding(context) -> bool:
	return environment.has_team_binding(context)

func inspection_evidence(context, target: int) -> Dictionary:
	return environment.inspection_evidence(context, target)

func prepare_reservation(context, offer: Dictionary, duration: float = 4.0) -> Dictionary:
	return environment.prepare_reservation(context, offer, duration)

func publish_checked(context, points: PackedVector3Array) -> void:
	environment.publish_checked(context, points)

func register(context) -> bool:
	return environment.register(context)

func rollback_reservation(context, token: Dictionary) -> void:
	environment.rollback_reservation(context, token)

func team_configuration_revision(context) -> int:
	return environment.team_configuration_revision(context)

func team_level(context, legacy_level: int = 0) -> int:
	return environment.team_level(context, legacy_level)

func validate_reservation(context, token: Dictionary) -> bool:
	return environment.validate_reservation(context, token)
