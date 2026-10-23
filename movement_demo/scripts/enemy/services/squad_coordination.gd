extends RefCounted

## Owned by one explicitly configured squad; unbound actors have no team tasks.
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
var _coordination_diagnostics: Dictionary = {}
var _coordination_checked: Dictionary = {}
var _inspection_orders: Dictionary = {}
var _team_planner = TeamPlanner.new()
const COORDINATION_PERIOD := 0.2 # Implementation default, not a user constraint.
const COORDINATION_ACCEPT_SECONDS := 1.0
const COORDINATION_WAIT_SECONDS := 2.0
const COORDINATION_MAX_SECONDS := 20.0
const COORDINATION_SOURCE_DISTANCE := 0.5
const COORDINATION_REPORT_SECONDS := 0.35
const FLANK_SIDE_MARGIN := 0.5
const FLANK_SEPARATION_COSINE := -0.5 # cos(120 degrees), horizontal directions.


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
	_advance_coordination()
	_advance_inspection_traffic()
	last_advance_usec = Time.get_ticks_usec() - started

func reset() -> void:
	for team_id in _coordination_plans.keys(): _drop_coordination_plan(team_id, &"reset")
	_clear_coordination()

func release_member(id: int) -> void:
	_coordination_baselines.erase(id)
	_coordination_offers.erase(id)
	_invalidate_coordination_member(id, &"member_released")

func invalidate_member(id: int) -> void:
	_coordination_offers.erase(id)
	_coordination_baselines.erase(id)
	_invalidate_coordination_member(id, &"member_version_changed")

func append_snapshot(context, target: int, result: Dictionary) -> void:
	var id: int = context.actor.get_instance_id()
	var source := coordination_source(context, target)
	# Only accepted plan requests are appended below. Raw status requests were
	# already projected by the area, so an absent plan needs no second member scan.
	if not source.is_empty() and _coordination_plans.has(source.team_id):
		for need: Dictionary in _coordination_requests(_coordination_team_members(source.team_id), source):
			if not need.get("accepted", false) or need.actor_id == id: continue
			result.requests.append({"id": need.request_id, "request_id": need.request_id, "kind": need.kind, "preparing": not need.get("actual", false),
				"target_id": target, "beneficiary_id": need.actor_id, "lane_id": &"target",
				"position": _context(need.actor_id).actor.global_position, "remaining": maxf(0.0, need.valid_until - elapsed)})


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

func reload_opportunity(context) -> Dictionary:
	var result := {"allowed": false, "support_seconds": 0.0, "provider_id": 0, "request_id": 0}
	if not context.cooperation_enabled(): return result
	var id: int = context.actor.get_instance_id()
	var data: Dictionary = context.cooperation_snapshot()
	for member in data.members:
		var other = _context(int(member.id))
		if member.id != id and other != null and other.actor.ammo.is_reloading: return result
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
	_coordination_diagnostics.clear()
	_inspection_orders.clear()
	_coordination_baselines.clear()
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

## Return the validated contact identity, or -1 for an unauthorized source.
## Personal/noise/investigation evidence has no renewed-contact identity (0).
func _coordination_source_contact(context, source: Dictionary) -> int:
	if _coordination_team(context) == 0: return -1
	if typeof(source.get("source_id")) != TYPE_INT or source.source_id <= 0: return -1
	if typeof(source.get("target_id")) != TYPE_INT or source.target_id < 0: return -1
	if not source.get("position") is Vector3 or not source.position.is_finite(): return -1
	if not _reservation_text(source.get("source")): return -1
	if not _reservation_number(source.get("captured_at")) or not _reservation_number(source.get("valid_until")): return -1
	if source.captured_at < 0.0 or source.captured_at > context.evidence_elapsed_seconds or source.valid_until <= context.evidence_elapsed_seconds: return -1
	if source.target_id == 0:
		return 0 if source.source in [&"noise", &"sound"] and context.noise_search_origin.is_finite() and context.noise_search_origin.distance_squared_to(source.position) < 0.0001 else -1
	if source.target_id != context.cooperation_target_id(): return -1
	# The Context event bridge is the source authority; this additionally checks
	# against acquired observation values, never the hidden target's transform.
	if source.source == &"visual":
		return 0 if context.sees_player and context.last_seen_position.distance_squared_to(source.position) < 0.0001 else -1
	if source.source in [&"visual_loss", &"close_cover_exact", &"inspection"]:
		var inspected := inspection_evidence(context, source.target_id)
		return 0 if not inspected.is_empty() and int(inspected.id) == source.source_id and inspected.position.distance_squared_to(source.position) < 0.0001 else -1
	if source.source in [&"shared_visual", &"observation_memory"]:
		if source.source == &"observation_memory" and source.valid_until > source.captured_at + maxf(0.1, context.setting(&"cooperation", &"cover_inspection_seconds", 20.0)) + 0.0001: return -1
		return environment.observation_contact_id(context, source.source_id, source.target_id, source.position)
	return -1

## Input timestamps use Context time. A duplicate source event cannot refresh
## its timestamp or deadline; only a genuinely acquired newer source can do so.

func publish_noise_source(context, position: Vector3) -> void:
	if not context.cooperation_enabled() or not position.is_finite(): return
	var source_id: int = environment.allocate_coordination_id()
	var captured: float = context.evidence_elapsed_seconds
	publish_coordination_source(context, {"source_id": source_id, "source": &"noise", "target_id": 0,
		"position": position, "captured_at": captured,
		"valid_until": captured + maxf(0.1, context.setting(&"cooperation", &"cover_inspection_seconds", 20.0))})

func publish_coordination_source(context, source: Dictionary) -> void:
	var contact_id := _coordination_source_contact(context, source)
	if contact_id < 0: return
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
	# The area validated the identity above; a reacquisition contradicts old
	# search progress even at one point. Never trust a caller-supplied identity.
	if contact_id > 0 and contact_id < int(previous.get("contact_id", 0)): return
	# A newer sight at another location contradicts an older investigation. An
	# older, longer-lived clue at the SAME frozen anchor remains a valid fallback.
	if not previous.is_empty() and captured < previous.captured_at and previous.position.distance_to(source.position) >= COORDINATION_SOURCE_DISTANCE: return
	var new_anchor: bool = previous.is_empty() or previous.position.distance_to(source.position) >= COORDINATION_SOURCE_DISTANCE or contact_id > int(previous.get("contact_id", 0))
	var evidence_id: int = int(previous.get("evidence_id", 0))
	if new_anchor:
		evidence_id = environment.allocate_coordination_id()
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
		"evidence_id": evidence_id, "contact_id": maxi(contact_id, int(previous.get("contact_id", 0))), "generation": generation, "team_id": team_id}
	if new_anchor:
		_coordination_due[team_id] = elapsed
		environment.notify_coordination_changed()

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

## Strong squads decide the investigation objective before comparing local
## movement offers. Stable slots belong to this evidence, not current positions.
func inspection_order(context) -> Dictionary:
	if not has_team_binding(context) or not context.coordinated_cooperation_enabled() or not context.can_use_action(&"search"): return {}
	var team_id := _coordination_team(context)
	var order: Dictionary = _inspection_orders.get(team_id, {})
	if order.is_empty() or environment.has_visual_contact(context, context.cooperation_target_id()): return {}
	var source := coordination_source(context, context.cooperation_target_id())
	if source.is_empty() or order.evidence_id != source.evidence_id: return {}
	return order.slots.get(context.actor.get_instance_id(), {}).duplicate(true)

## The squad owns passage through the planned ingress corridors. Waiting here
## is normal formation progress, not a personal stuck/repath/dissolve request.
func inspection_motion(context, slot: Dictionary, goal: Vector3, delta: float) -> Dictionary:
	if slot != inspection_order(context) or not slot.has("approach"): return {}
	var order: Dictionary = _inspection_orders[_coordination_team(context)]
	return _inspection_passage(context, order, slot, goal, delta)

## Read-only diagnostics use the same live order and passage calculation as
## execution. Inspecting the backend cannot advance a repair or renew a lease.
func inspection_status(context) -> Dictionary:
	var slot := inspection_order(context)
	if slot.is_empty(): return {}
	var order: Dictionary = _inspection_orders[_coordination_team(context)]
	var traffic: Dictionary = order.get("traffic", {})
	var state: Dictionary = context.coordination_motion_state()
	var entry := _assignment_for_owner(state.actor_id)
	var goal: Vector3 = slot.get("entry", Vector3.INF) if traffic.get("phase") != &"crossing" else slot.peek
	var passage: Dictionary = _inspection_passage(context, order, slot, goal, 0.0) if slot.has("approach") and slot.has("entry") else {}
	return {"order_id": order.order_id, "generation": generation, "plan_id": entry.get("plan_id", 0),
		"assignment_id": entry.get("assignment_id", 0), "assignment_revision": entry.get("assignment_revision", 0),
		"motion_revision": traffic.get("repairs", 0), "role": entry.get("role", &"assembly"),
		"phase": traffic.get("phase", &"preparing"), "position": state.position, "staging_position": slot.get("entry", Vector3.INF),
		"goal": traffic.get("goals", {}).get(state.actor_id, goal), "expires_at": entry.get("expires_at", slot.expires_at),
		"waiting_for": passage.get("waiting_for", []).duplicate(), "state": passage.get("motion_state", &"waiting"),
		"reason": passage.get("motion_reason", &"preparing"), "last_report": entry.get("execution_state", &"unaccepted")}

## Debug reads frozen plans and real feedback only; no candidate/nav queries.
## No stored route means no line: a destination is not a planned straight path.
func debug_member_snapshot(context) -> Dictionary:
	var result := inspection_status(context)
	var owner: int = context.actor.get_instance_id()
	var slot := inspection_order(context)
	if not slot.is_empty():
		var order: Dictionary = _inspection_orders[_coordination_team(context)]
		var traffic: Dictionary = order.get("traffic", {})
		var crossing: bool = traffic.get("phase") == &"crossing"
		result.source = &"inspection"
		result.route = traffic.get("routes", {}).get(owner, slot.get("crossing" if crossing else "approach", PackedVector3Array())).duplicate()
		result.next_route = PackedVector3Array() if crossing else slot.get("crossing", PackedVector3Array()).duplicate()
		result.target_position = slot.get("peek", Vector3.INF)
		result.remaining_seconds = maxf(0.0, float(result.expires_at) - elapsed)
		result.order_phase = _coordination_plans.get(_coordination_team(context), {}).get("phase", &"preparing")
		return result
	var entry := _assignment_for_owner(owner)
	if entry.is_empty():
		var diagnostic: Dictionary = _coordination_diagnostics.get(_coordination_team(context), {})
		var source := coordination_source(context, context.cooperation_target_id())
		return {"source": &"pending" if not source.is_empty() and context.cooperation_level() == 2 else &"personal",
			"phase": &"planning", "state": &"unassigned", "reason": diagnostic.get("reason", &"awaiting_candidates"),
			"planning_reason": diagnostic.get("reason", &"awaiting_candidates"),
			"assigned_count": diagnostic.get("assigned_count", 0), "member_count": diagnostic.get("member_count", 0),
			"offer_count": _coordination_offers.get(owner, []).size(),
			"available_in": context.coordination_motion_state().get("available_in", 0.0),
			"remaining_seconds": maxf(0.0, float(source.get("valid_until", elapsed)) - elapsed)}
	var plan: Dictionary = _coordination_plans.get(entry.team_id, {})
	result = {"source": &"assignment", "plan_id": entry.plan_id, "assignment_id": entry.assignment_id,
		"assignment_revision": entry.assignment_revision, "role": entry.role,
		"accepted": entry.accepted, "constraint_mode": entry.get("constraint_mode", &"coordinated"),
		"phase": plan.get("phase", &"assigning"), "state": entry.get("execution_state", &"unaccepted"),
		"staging_position": entry.get("staging_position", Vector3.INF),
		"target_position": entry.get("selected_position", Vector3.INF),
		"goal": entry.get("selected_position", Vector3.INF), "remaining_seconds": maxf(0.0, float(entry.expires_at) - elapsed),
		"waiting_for": entry.get("waiting_for", []).duplicate(), "reason": entry.get("motion_reason", &"")}
	for offer: Dictionary in entry.reserved_offers:
		if offer.offer_key != entry.get("selected_offer_key", entry.allowed_offer_keys[0]): continue
		if not entry.accepted:
			result.goal = offer.position
			result.target_position = offer.position
			result.staging_position = offer.path_summary.staging_position
		var path: Array = offer.path_summary.get("planned_path", [])
		if not path.is_empty(): result.route = PackedVector3Array(path)
		break
	return result

func _inspection_passage(context, order: Dictionary, slot: Dictionary, goal: Vector3, delta: float) -> Dictionary:
	var helper = preload("res://scripts/enemy/services/enemy_search_formation.gd")
	var approaching: bool = goal.is_equal_approx(slot.entry)
	var state: Dictionary = context.coordination_motion_state()
	var position: Vector3 = state.position
	var stopped := {"next": position, "stop": position, "distance": 0.0,
		"motion_state": &"waiting", "waiting_for": [], "motion_reason": &"preparing"}
	if order.slots.values().any(func(member): return not member.has("approach")):
		return stopped
	var traffic: Dictionary = order.get("traffic", {})
	stopped.motion_revision = traffic.get("repairs", 0)
	var owner: int = state.actor_id
	if traffic.is_empty() or traffic.phase != (&"approach" if approaching else &"crossing"):
		return stopped
	if float(state.get("available_in", 0.0)) > 0.0:
		stopped.motion_reason = state.get("availability_reason", &"execution_busy")
		return stopped
	var remaining: PackedVector3Array = helper.remaining_path(position, traffic.routes.get(owner, slot.approach if approaching else slot.crossing))
	var repair_priority: int = traffic.priority_moves.find(owner)
	if traffic.holds.has(owner):
		stopped.waiting_for = [traffic.holds[owner]]
		stopped.motion_reason = &"yield"
		return stopped
	goal = traffic.goals.get(owner, goal)
	if position.distance_to(goal) <= 0.025:
		stopped.motion_reason = &"assembly_barrier" if approaching else &"observing"
		stopped.temporary_goal = traffic.goals.get(owner, Vector3.INF)
		if approaching:
			stopped.waiting_for = order.slots.keys().filter(func(id): return id != owner and _context(id) != null and _context(id)._horizontal_distance(order.slots[id].entry) > 0.025)
		return stopped
	var next: Vector3 = remaining[1] if remaining.size() > 1 else goal
	var allowed: float = position.distance_to(next)
	var waiting_for: Array = []
	var reason: StringName = &""
	for id: int in order.slots:
		if id == owner: continue
		var other = _context(id)
		if other == null: continue
		var clearance: float = float(slot.spacing) - 0.06
		var other_state: Dictionary = other.coordination_motion_state()
		var point: Vector3 = other_state.position
		# Both measured occupancy and the next physical step remain protected,
		# regardless of passage priority or whether that member has arrived.
		var available: float = helper.corridor_entry(position, next, point, point + other_state.velocity * delta, clearance, true)
		allowed = minf(allowed, available)
		if available <= 0.01:
			waiting_for.append(id)
			reason = &"occupied"
		var other_slot: Dictionary = order.slots[id]
		var priority: int = slot.passage_priority if approaching else slot.crossing_priority
		var other_priority: int = other_slot.passage_priority if approaching else other_slot.crossing_priority
		var other_repair: int = traffic.priority_moves.find(id)
		var precedes: bool = other_repair >= 0 and (repair_priority < 0 or other_repair < repair_priority)
		if repair_priority < 0 and other_repair < 0: precedes = other_priority < priority
		if not precedes or traffic.holds.has(id) or not other_slot.has("approach"): continue
		var path: PackedVector3Array = helper.remaining_path(point, traffic.routes.get(id, other_slot.approach if approaching else other_slot.crossing))
		if other_repair < 0 and approaching and slot.get("ordered_departures", false) and helper.paths_conflict(remaining, path, clearance):
			allowed = 0.0
			if not waiting_for.has(id): waiting_for.append(id)
			if reason.is_empty(): reason = &"passage_order"
			continue
		# Reserve only the untraversed corridor. Following members can approach
		# its moving boundary while a predecessor advances; a distant conflict
		# must not lock their entire trip. Actual body clearance still applies.
		# A member initially occupying a predecessor's passage may leave it
		# only when its assigned destination fully clears that passage. Merely
		# moving sideways and parking inside it would trap the predecessor.
		var clears_passage := true
		for i in range(1, path.size()):
			var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(goal, path[i - 1], path[i])
			if context._horizontal_distance_between(goal, nearest) < clearance: clears_passage = false
		for i in range(1, path.size()):
			available = helper.corridor_entry(position, next, path[i - 1], path[i], clearance, clears_passage)
			allowed = minf(allowed, available)
			if available <= 0.01 and not waiting_for.has(id):
				waiting_for.append(id)
				if reason.is_empty(): reason = &"passage_order"
	var direction: Vector3 = (next - position).normalized()
	return {"next": next, "stop": position + direction * allowed, "distance": allowed,
		"motion_state": &"moving" if allowed > 0.01 else (&"blocked" if reason == &"occupied" else &"waiting"),
		"waiting_for": waiting_for, "motion_reason": &"repair" if traffic.priority_moves.has(owner) else reason,
		"temporary_goal": traffic.goals.get(owner, Vector3.INF), "repairs": traffic.repairs, "motion_revision": traffic.repairs}

## Waiting permissions alone cannot resolve a cycle caused by occupied routes.
## Progress belongs to each member. A third member walking elsewhere cannot
## hide two mutually blocked members. Queries never advance this state.
func _advance_inspection_traffic() -> void:
	for team_id: int in _inspection_orders:
		var order: Dictionary = _inspection_orders[team_id]
		if order.slots.is_empty() or order.slots.values().any(func(slot): return not slot.has("entry") or not slot.has("passage_priority")): continue
		var plan: Dictionary = _coordination_plans.get(team_id, {})
		var crossing: bool = plan.get("tactic") == &"inspect" and plan.get("phase") == &"executing" and float(plan.get("release_at", INF)) <= elapsed
		_update_inspection_traffic(order, not crossing)

func _update_inspection_traffic(order: Dictionary, approaching: bool) -> void:
	var phase: StringName = &"approach" if approaching else &"crossing"
	if order.get("traffic", {}).get("phase") != phase:
		order.traffic = {"phase": phase, "positions": {}, "progress_at": {}, "waiting_for": {},
			"next_repair": elapsed, "repairs": 0, "priority_moves": [], "routes": {}, "goals": {}, "holds": {}, "yield_for": {}}
	var traffic: Dictionary = order.traffic
	var waiting: Array = []
	for id: int in order.slots:
		var member = _context(id)
		if member == null: continue
		var execution := _assignment_for_owner(id)
		if approaching and execution.get("execution_state") == &"blocked" and execution.get("motion_reason") == &"static_crossing":
			_fail_inspection_traffic(order)
			return
		var position: Vector3 = member.coordination_motion_state().position
		if not traffic.positions.has(id) or position.distance_to(traffic.positions[id]) >= 0.08:
			traffic.positions[id] = position
			traffic.progress_at[id] = elapsed
		var slot: Dictionary = order.slots[id]
		var goal: Vector3 = traffic.goals.get(id, slot.entry if approaching else slot.peek)
		if member._horizontal_distance(goal) > 0.025: waiting.append(id)
	for arrived: int in traffic.priority_moves.duplicate():
		if waiting.has(arrived): continue
		if traffic.yield_for.has(arrived):
			traffic.holds[arrived] = traffic.yield_for[arrived]
			traffic.yield_for.erase(arrived)
			traffic.goals.erase(arrived)
			traffic.routes.erase(arrived)
		traffic.priority_moves.erase(arrived)
	for id: int in traffic.holds.keys():
		if not waiting.has(traffic.holds[id]):
			traffic.holds.erase(id)
			traffic.progress_at[id] = elapsed
	if waiting.is_empty() or elapsed < float(traffic.next_repair): return
	traffic.waiting_for.clear()
	for id: int in waiting:
		var slot: Dictionary = order.slots[id]
		traffic.waiting_for[id] = _inspection_passage(_context(id), order, slot, slot.entry if approaching else slot.peek, 0.0).waiting_for
	var blocked: Array = waiting.filter(func(id): return not _inspection_dependency_advancing(id, waiting, traffic, []))
	if blocked.is_empty(): return
	traffic.next_repair = elapsed + 0.5
	if traffic.repairs >= order.slots.size() * 2:
		_fail_inspection_traffic(order)
		return
	blocked.sort_custom(func(a, b): return order.slots[a].passage_priority < order.slots[b].passage_priority if approaching else order.slots[a].crossing_priority < order.slots[b].crossing_priority)
	# First change passage order using a locally validated route. Only if no
	# member can progress do we ask a blocker to vacate a concrete holding point.
	for id: int in blocked:
		var member = _context(id)
		if not member.coordination_motion_state().movable or traffic.holds.has(id): continue
		var slot: Dictionary = order.slots[id]
		var goal: Vector3 = traffic.goals.get(id, slot.entry if approaching else slot.peek)
		var occupied: Array = []
		for other: int in order.slots:
			if other != id and _context(other) != null: occupied.append(_context(other).coordination_motion_state().position)
		var route: PackedVector3Array = member.inspection_route(slot, goal, occupied, traffic.routes.get(id, slot.approach if approaching else slot.crossing))
		if route.is_empty(): continue
		traffic.routes[id] = route
		traffic.priority_moves.erase(id)
		traffic.priority_moves.append(id)
		traffic.repairs += 1
		traffic.progress_at[id] = elapsed
		return
	for id: int in blocked:
		var goal: Vector3 = order.slots[id].entry if approaching else order.slots[id].peek
		# Free a destination before a merely intermediate obstruction. Otherwise
		# a three-way swap can require several pointless out-and-back detours.
		var blockers: Array = order.slots.keys().filter(func(other): return other != id and _context(other) != null and _context(other)._horizontal_distance(goal) < float(order.slots[id].spacing) - 0.06)
		for other: int in traffic.waiting_for.get(id, []):
			if not blockers.has(other): blockers.append(other)
		for blocker: int in blockers:
			if traffic.holds.has(blocker) or not order.slots.has(blocker): continue
			var member = _context(blocker)
			if member == null or not member.coordination_motion_state().movable: continue
			if _assignment_for_owner(blocker).get("complete", false): continue
			var occupied: Array = []
			var destinations: Array = []
			for other: int in order.slots:
				if other != blocker and _context(other) != null: occupied.append(_context(other).coordination_motion_state().position)
				destinations.append(order.slots[other].entry if approaching else order.slots[other].peek)
			var route: PackedVector3Array = preload("res://scripts/enemy/services/enemy_search_formation.gd").yield_route(member, order.slots[blocker], occupied, destinations)
			if route.is_empty(): continue
			traffic.routes[blocker] = route
			traffic.goals[blocker] = route[-1]
			traffic.yield_for[blocker] = id
			traffic.priority_moves.erase(blocker)
			traffic.priority_moves.append(blocker)
			traffic.repairs += 1
			traffic.progress_at[blocker] = elapsed
			return
	_fail_inspection_traffic(order)

func _fail_inspection_traffic(order: Dictionary) -> void:
	# Exhausting legal repair candidates is a layout failure, never a checked
	# observation. Reuse the original finite whole-party fallback once.
	for slot: Dictionary in order.slots.values():
		if not order.failed_sides.has(slot.side): order.failed_sides.append(slot.side)
	var context = _context(order.members[0])
	if context != null:
		var team_id := _coordination_team(context)
		_drop_coordination_plan(team_id, &"traffic_blocked")
		_coordination_due[team_id] = elapsed

func _inspection_dependency_advancing(id: int, waiting: Array, traffic: Dictionary, visited: Array) -> bool:
	if not waiting.has(id) or visited.has(id): return false
	var member = _context(id)
	if member != null and float(member.coordination_motion_state().get("available_in", 0.0)) > 0.0: return true
	var assignment := _assignment_for_owner(id)
	if not assignment.is_empty() and not assignment.accepted and elapsed < float(assignment.accept_until): return true
	if elapsed - float(traffic.progress_at.get(id, elapsed)) < 0.35: return true
	visited = visited.duplicate()
	visited.append(id)
	for other: int in traffic.waiting_for.get(id, []):
		if _inspection_dependency_advancing(other, waiting, traffic, visited): return true
	return false

## Local actions report only feasibility for their exact current slot. A failed
## layout must not keep filtering everybody's choices until the clue expires.
func report_inspection_preparation(context, slot: Dictionary, available: bool, approach_seconds: float = 0.0) -> void:
	if slot.is_empty() or slot != inspection_order(context): return
	var team_id := _coordination_team(context)
	var order: Dictionary = _inspection_orders[team_id]
	if available:
		approach_seconds = maxf(approach_seconds, float(slot.get("staging_seconds", 0.0)))
		# Allow the measured assembly journey, not only two seconds from order
		# creation. Capture it once per member; polling cannot renew the deadline.
		var id: int = context.actor.get_instance_id()
		if not order.prepared_members.has(id) and is_finite(approach_seconds) and approach_seconds >= 0.0:
			order.prepared_members.append(id)
			order.prepare_until = maxf(order.prepare_until, minf(order.expires_at, order.created_at + approach_seconds + COORDINATION_WAIT_SECONDS))
		return
	if not order.failed_sides.has(slot.side): order.failed_sides.append(slot.side)
	_coordination_due[team_id] = elapsed

func _prepare_inspection_order(team_id: int, source: Dictionary, ids: Array) -> void:
	var representative = _context(ids[0])
	if not has_team_binding(representative) or not representative.coordinated_cooperation_enabled(): return
	var clue: Dictionary = representative.cover_inspection_evidence()
	if clue.is_empty() or environment.has_visual_contact(representative, source.target_id):
		_inspection_orders.erase(team_id)
		return
	var clock_offset: float = representative.evidence_elapsed_seconds - elapsed
	clue.captured_at = float(clue.captured_at) - clock_offset
	clue.valid_until = float(clue.valid_until) - clock_offset
	var eligible: Array = []
	var spacing := 1.2
	for id: int in ids:
		var member = _context(id)
		if not _coordination_role_allowed(member, source.target_id, &"inspect_left"): continue
		eligible.append(id)
		var motion: Dictionary = member.coordination_motion_state()
		spacing = maxf(spacing, float(motion.radius) * 2.0 + float(motion.spacing_margin) + 0.2)
	if eligible.size() < 2:
		_inspection_orders.erase(team_id)
		return
	eligible.sort()
	var old: Dictionary = _inspection_orders.get(team_id, {})
	# The squad chooses one investigation objective, even when no wall was hit
	# by the last visual ray. Members consume this frozen goal, not separate
	# guesses made while they advance.
	if old.get("evidence_id") == source.evidence_id and old.has("clue"):
		clue = old.clue.duplicate(true)
	var body = clue.get("cover")
	if body is WeakRef: body = body.get_ref()
	if not is_instance_valid(body) and (old.get("evidence_id") != source.evidence_id or not old.has("clue")):
		var inferred: Dictionary = preload("res://scripts/enemy/services/enemy_cover_inspection_geometry.gd").nearby_investigation_cover(representative, clue)
		if not inferred.is_empty():
			clue.merge(inferred, true)
			body = clue.cover.get_ref()
	var box := body.get_node_or_null("CollisionShape3D") as CollisionShape3D if is_instance_valid(body) else null
	var geometry_key: Array = [body.get_instance_id() if is_instance_valid(body) else 0, box.global_transform if box != null else Transform3D.IDENTITY,
		box.shape.size if box != null and box.shape is BoxShape3D else Vector3.ZERO,
		box.disabled if box != null else true, body.collision_layer if is_instance_valid(body) else 0,
		eligible.map(func(id): return _members[id].navigation_revision)]
	var kind: StringName = &"cover" if box != null else &"point"
	var layout := 0 if kind == &"cover" else 1
	var attempted: Array = []
	if old.get("evidence_id") == source.evidence_id and old.get("members") == eligible and old.get("geometry_key") == geometry_key:
		if old.slots.is_empty(): return
		var current: Dictionary = _coordination_plans.get(team_id, {})
		if not current.is_empty() and current.tactic == &"inspect": return
		if old.failed_sides.is_empty() and elapsed < float(old.prepare_until): return
		attempted = old.attempted.duplicate()
		if old.kind == &"point":
			old.slots.clear()
			environment.notify_coordination_changed()
			return
		# Prefer the side whose local routes did not fail. Every alternative is
		# tried at most once for this evidence/member set, with a finite window.
		var alternatives: Array = [1, -1] if old.failed_sides.has(-1) else [-1, 1]
		var next: Array = alternatives.filter(func(side): return not attempted.has(side))
		if next.is_empty():
			kind = &"point"
			layout = 1
		else: layout = next[0]
	if kind == &"cover": attempted.append(layout)
	else: attempted.append(&"point")
	var ordered := eligible.duplicate()
	var right: Vector3 = Vector3.UP.cross(source.front_axis)
	if kind == &"cover" and box != null and box.shape is BoxShape3D:
		var origin: Vector3 = box.to_local(clue.observer_position)
		var half: Vector3 = box.shape.size * 0.5
		right = box.global_basis.x.normalized() if absf(origin.z) / maxf(0.01, half.z) >= absf(origin.x) / maxf(0.01, half.x) else box.global_basis.z.normalized()
	ordered.sort_custom(func(a, b): return _context(a).actor.global_position.dot(right) < _context(b).actor.global_position.dot(right))
	var sides := [[], []]
	var contexts := {}
	for id: int in eligible: contexts[id] = _context(id)
	# Preserve lateral ordering so members do not exchange sides through one
	# another. Choose the split from checked routes, not odd/even head count.
	if layout != 0:
		sides[0 if layout < 0 else 1] = ordered
	else:
		var costs: Dictionary = preload("res://scripts/enemy/services/enemy_search_formation.gd").entry_travel_seconds(contexts,
			{"kind": kind, "clue": clue, "spacing": spacing, "layout": layout})
		var split := ceili(ordered.size() * 0.5)
		var best_finish := INF
		var best_total := INF
		var cuts: Array = [split]
		for cut in range(1, ordered.size()):
			if cut != split: cuts.append(cut)
		for cut: int in cuts:
			var finish := 0.0
			var total := 0.0
			for index in ordered.size():
				var id: int = ordered[index]
				var side := -1 if index < cut else 1
				var state: Dictionary = contexts[id].coordination_motion_state()
				var depth: int = cut if side < 0 else ordered.size() - cut
				var travel: float = costs[id][side]
				finish = maxf(finish, float(state.get("available_in", 0.0)) + travel + (depth - 1) * spacing / maxf(0.1, state.move_speed))
				total += travel
			if finish < best_finish - 0.1 or (absf(finish - best_finish) <= 0.1 and total < best_total - 0.25):
				split = cut
				best_finish = finish
				best_total = total
		sides = [ordered.slice(0, split), ordered.slice(split)]
	var slots := {}
	var order_expires: float = minf(source.valid_until, elapsed + float(representative.setting(&"cooperation", &"cover_inspection_plan_seconds", 16.0)))
	if old.get("evidence_id") == source.evidence_id:
		order_expires = minf(order_expires, float(old.expires_at))
	var order_id: int = environment.allocate_coordination_id()
	for side in 2:
		for row in sides[side].size():
			slots[sides[side][row]] = {"side": -1 if side == 0 else 1, "row": row,
				"depth": sides[side].size(), "spacing": spacing, "members": eligible.duplicate(), "layout": layout,
				"kind": kind, "clue": clue.duplicate(true), "front_axis": source.front_axis,
				"order_id": order_id, "evidence_id": source.evidence_id, "target_id": source.target_id,
				"issued_at": elapsed, "expires_at": order_expires,
				"release_condition": &"all_staged"}
	preload("res://scripts/enemy/services/enemy_search_formation.gd").prepare_slots(contexts, slots)
	_inspection_orders[team_id] = {"order_id": order_id, "evidence_id": source.evidence_id, "members": eligible, "slots": slots,
		"kind": kind, "clue": clue.duplicate(true),
		"attempted": attempted, "failed_sides": [], "created_at": elapsed, "expires_at": slots.values()[0].expires_at,
		"prepared_members": [], "prepare_until": elapsed + COORDINATION_WAIT_SECONDS, "geometry_key": geometry_key}
	var previous_plan: Dictionary = _coordination_plans.get(team_id, {})
	if not previous_plan.is_empty() and previous_plan.tactic != &"inspect":
		_drop_coordination_plan(team_id, &"whole_squad_search")
	environment.notify_coordination_changed()

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
	if context.coordinated_cooperation_enabled() and mobile and not context.sees_player and not environment.has_visual_contact(context, target_id) and context.can_use_action(&"search") and (context.is_alerted or context.noise_search_origin.is_finite()):
		result.append(&"search_sector")
		if target_id != 0:
			result.append(&"inspect_left")
			result.append(&"inspect_right")
			result.append(&"inspect_follow")
	if not context.cover_inspection_evidence().is_empty() and not environment.has_visual_contact(context, target_id): return result
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
	if role in [&"search_sector", &"inspect_left", &"inspect_right", &"inspect_follow"]:
		if environment.has_visual_contact(context, target_id): return false
		if role != &"search_sector" and target_id == 0: return false
		return context.coordinated_cooperation_enabled() and context.actor.can_move() and not context.actor.is_vaulting() and not context.actor.melee_active and not context.sees_player and context.can_use_action(&"search")
	if target_id == 0: return false
	if not context.cover_inspection_evidence().is_empty() and not environment.has_visual_contact(context, target_id): return false
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
	var owners: Array = [&"search"] if offer.role in [&"inspect_left", &"inspect_right", &"inspect_follow", &"search_sector"] else [&"cooperate"]
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
	if offer.role in [&"inspect_left", &"inspect_right", &"inspect_follow"]:
		var order := inspection_order(context)
		if offer.role == &"inspect_follow" and order.is_empty(): return false
		if not order.is_empty():
			if summary.get("formation_row") != order.row or summary.get("side") != order.side: return false
			if summary.get("formation_layout", 0) != order.get("layout", 0): return false
			if (order.row > 0) != (offer.role == &"inspect_follow"): return false
	if offer.role == &"search_sector" and summary.has("sector_key"):
		if not context.has_method("coordination_search_template_valid") or not context.coordination_search_template_valid(String(summary.sector_key), int(summary.get("source_revision", -1)), int(summary.get("template_navigation_revision", -1))): return false
	if not summary.get("staging_position") is Vector3 or not summary.staging_position.is_finite(): return false
	if not _reservation_number(summary.get("staging_seconds")) or summary.staging_seconds < 0.0: return false
	if not _coordination_frame_valid(summary, source, StringName(offer.role), offer.position, has_team_binding(context) and context.coordinated_cooperation_enabled()): return false
	if offer.role in [&"inspect_left", &"inspect_right", &"inspect_follow", &"search_sector"]:
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

func coordination_offer_available(context, offer: Dictionary) -> bool:
	return _coordination_offer_valid(context, offer)

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
		_coordination_environments[team_id] = {"signature": signature, "revision": environment.allocate_coordination_id()}
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
	if primary.is_empty() and (pending.is_empty() or pending.accept_until <= elapsed) and not (entry.get("constraint_mode") == &"advisory" and not entry.accepted): return false
	if not entry.accepted and entry.accept_until <= elapsed: return false
	return true

## A cheap decision hint only. Acceptance still uses the complete live contract;
## this never grants permission or exposes the internal assignment dictionaries.

func assignment_decision_revision(context) -> int:
	var owner_id: int = context.actor.get_instance_id()
	var team_id: int = _team_by_member.get(owner_id, 0)
	var order: Dictionary = _inspection_orders.get(team_id, {})
	var order_revision: int = order.get("order_id", 0) if order.get("slots", {}).has(owner_id) else 0
	var plan: Dictionary = _coordination_plans.get(team_id, {})
	for entry: Dictionary in plan.get("assignments", []):
		if entry.actor_id == owner_id:
			return hash([generation, order_revision, plan.plan_id, entry.assignment_id, entry.assignment_revision])
	return hash([generation, order_revision]) if order_revision != 0 else 0

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
	reservation.merge({"reservation_id": entry.reservation_id, "assignment_id": entry.assignment_id, "coordinator_id": get_instance_id(),
		"owner_id": entry.actor_id, "owner_action": entry.owner_action, "offer_key": first.offer_key,
		"position_set_key": first.position_set_key, "path_summary": _reservation_summary(first.path_summary),
		"scope": &"tactical", "role": entry.role, "target_id": plan.target_id, "evidence_id": plan.evidence_id,
		"phase": &"pending", "created_at": elapsed, "expires_at": entry.expires_at, "accept_until": entry.accept_until,
		"selected_offer_key": "", "alternatives": entry.reserved_offers.duplicate(true)})
	return reservation

func prepare_assignment(context, identity: Dictionary, offer_key: String) -> Dictionary:
	var entry := _assignment_token(context, identity)
	if entry.is_empty() or not entry.allowed_offer_keys.has(offer_key) or not _advisory_slot_available(context, entry): return {}
	if entry.accepted and not entry.get("segment_boundary", false): return {}
	var selected: Dictionary = {}
	for option: Dictionary in entry.reserved_offers:
		if option.offer_key == offer_key: selected = option
	if selected.is_empty(): return {}
	var existing_pending: Dictionary = environment.reservation_value(entry.get("pending_reservation_id", 0))
	if not existing_pending.is_empty() and existing_pending.offer_key == offer_key and _reservation_valid(existing_pending):
		return existing_pending.duplicate(true) if _reservation_position_available(context, existing_pending, existing_pending.reservation_id) else {}
	var reservation: Dictionary = environment.reservation_value(entry.reservation_id)
	if reservation.is_empty() and entry.get("constraint_mode") == &"advisory": reservation = _coordination_reservation(context, entry, _coordination_plans[entry.team_id])
	if reservation.is_empty() or not _reservation_valid(reservation): return {}
	var proposed := reservation.duplicate(true)
	proposed.merge({"position": selected.position, "offer_key": selected.offer_key,
		"position_set_key": selected.position_set_key, "path_summary": _reservation_summary(selected.path_summary),
		"selected_offer_key": selected.offer_key}, true)
	if not _reservation_position_available(context, proposed, int(reservation.reservation_id)): return {}
	if entry.accepted:
		# A different allowed segment gets a separate pending physical lease;
		# the task itself and its original deadline remain exactly the same.
		proposed.reservation_id = environment.allocate_coordination_id()
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
	if entry.is_empty() or not _advisory_slot_available(context, entry): return false
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
	if entry.role in [&"inspect_left", &"inspect_right", &"inspect_follow"] and report.get("state") not in [&"unavailable", &"self_preservation"]:
		var traffic: Dictionary = _inspection_orders.get(plan.team_id, {}).get("traffic", {})
		if int(report.get("motion_revision", 0)) != int(traffic.get("repairs", 0)): return false
	var state: StringName = report.get("state", &"")
	if state not in [&"moving", &"waiting", &"blocked", &"arrived", &"complete", &"unavailable", &"self_preservation"]: return false
	if not entry.accepted and state not in [&"unavailable", &"self_preservation"]: return false
	if not report.get("segment_boundary", false) is bool: return false
	if state in [&"unavailable", &"self_preservation"]:
		entry.failed = true
		entry.failure_reason = state
		_coordination_offers[entry.actor_id] = _coordination_offers.get(entry.actor_id, []).filter(func(offer): return not entry.allowed_offer_keys.has(offer.offer_key))
		environment.release_tactical_reservation(self, entry.reservation_id)
		environment.release_tactical_reservation(self, entry.get("pending_reservation_id", 0))
		# Self-preservation withdraws this member's capability. It says nothing
		# about whether the reserved standing position or route is obstructed.
		var held_post: bool = context.actor.global_position.distance_to(entry.get("selected_position", Vector3.INF)) <= 0.35 and (entry.role == &"front_support" or entry.reserved_offers[0].path_summary.get("holds_position", false))
		if state != &"self_preservation" and report.get("reason") != &"candidate_unavailable" and not held_post: _record_coordination_failure(entry, plan)
		_coordination_due[plan.team_id] = elapsed
		return true
	if report.get("execution_valid", true) != true: return false
	if state == &"arrived":
		if context.actor.global_position.distance_to(entry.staging_position) > 0.35 or context.actor.is_vaulting() or context.actor.melee_active: return false
		if entry.role not in [&"front_support", &"assisted_reload"] and not context.actor.can_move(): return false
	if state == &"complete":
		if entry.complete: return true
		if entry.role in [&"flank", &"inspect_left", &"inspect_right", &"inspect_follow"] and context.actor.global_position.distance_to(entry.selected_position) > 0.35: return false
		if plan.phase != &"executing" or plan.release_at < 0.0 or elapsed < plan.release_at: return false
		if entry.role in [&"inspect_left", &"inspect_right", &"inspect_follow", &"search_sector"]:
			if not _record_assignment_observations(context, entry, plan, report): return false
			for expected: Vector3 in entry.observation_points:
				if not entry.get("observed_points", {}).has(expected): return false
		entry.complete = true
	if state != &"complete" and plan.phase == &"executing" and plan.release_at >= 0.0 and elapsed >= plan.release_at:
		if not _record_assignment_observations(context, entry, plan, report): return false
	entry.last_report_at = elapsed
	entry.segment_boundary = report.get("segment_boundary", false)
	entry.position = context.actor.global_position
	entry.execution_state = state
	entry.waiting_for = report.get("waiting_for", []).duplicate()
	entry.motion_reason = report.get("motion_reason", &"")
	entry.ready_for_phase = state == &"arrived"
	entry.report_phase_id = plan.phase_id
	return true


## Incremental observations belong to this accepted assignment and version.
## Re-reporting a point never renews its original observation or expiry.

func _record_assignment_observations(context, entry: Dictionary, plan: Dictionary, report: Dictionary) -> bool:
	if entry.role not in [&"inspect_left", &"inspect_right", &"inspect_follow", &"search_sector"]: return true
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
			if not entry.accepted or entry.complete or not entry.role in [&"flank", &"team_position", &"assisted_reload", &"assisted_retreat", &"inspect_left", &"inspect_right", &"inspect_follow", &"search_sector"] or not _coordination_assignment_valid(plan, entry): continue
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
	if _coordination_checked.is_empty() or offer.role not in [&"inspect_left", &"inspect_right", &"inspect_follow", &"search_sector"]: return false
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
	_prepare_inspection_order(team_id, source, ids)
	# A complete team investigation replaces incompatible combat posts. Keep
	# preparation owned by the coordinator; do not wait for personal holds to end.
	var order: Dictionary = _inspection_orders.get(team_id, {})
	if not order.get("slots", {}).is_empty() and _coordination_plans.get(team_id, {}).get("tactic", &"inspect") != &"inspect":
		_drop_coordination_plan(team_id, &"search_handoff")
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
			"advisory_active": _assignment_for_owner(id).get("constraint_mode") == &"advisory" and _assignment_for_owner(id).get("accepted", false),
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
		if order.get("evidence_id") == source.evidence_id and not order.slots.is_empty():
			snapshot_value.search_members = order.members.duplicate()
			snapshot_value.search_sides = [-1, 1] if order.slots.values()[0].layout == 0 else [order.slots.values()[0].layout]
	for id: int in ids:
		var task: Dictionary = _assignment_for_owner(id)
		if task.get("role") == &"flank" and task.get("accepted", false): snapshot_value.flank_owner_ids.append(id)
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
			if entry.role == &"flank" and entry.execution_valid and not snapshot_value.flank_owner_ids.has(entry.actor_id): snapshot_value.flank_owner_ids.append(entry.actor_id)
			projected.assignments.append(entry)
		snapshot_value.current_plan = projected
	return snapshot_value

func _coordination_find_source(team_id: int, ids: Array) -> Dictionary:
	var current: Dictionary = _coordination_plans.get(team_id, {})
	if not current.is_empty(): return _coordination_plan_source(current)
	var representative = _context(ids[0])
	var inspection: Dictionary = representative.cover_inspection_evidence() if has_team_binding(representative) and representative.coordinated_cooperation_enabled() else {}
	var best: Dictionary = {}
	for key: String in _coordination_sources:
		if _coordination_sources[key].team_id != team_id: continue
		var source := _active_coordination_source(key)
		if source.is_empty() or (not best.is_empty() and source.captured_at <= best.captured_at): continue
		var order: Dictionary = _inspection_orders.get(team_id, {})
		var offered: bool = order.get("evidence_id") == source.evidence_id and not order.get("slots", {}).is_empty()
		# Decide to inspect a witnessed hideout before waiting for unrelated
		# personal combat offers. Local routes still authorize every real slot.
		if not inspection.is_empty() and inspection.position.distance_to(source.position) <= 0.5 and not environment.has_visual_contact(representative, source.target_id): offered = true
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
	entry.assignment_id = environment.allocate_coordination_id()
	entry.reservation_id = environment.allocate_coordination_id()
	entry.assignment_revision = 1
	entry.plan_id = plan.plan_id
	entry.plan_version = plan.plan_version
	entry.constraint_mode = plan.get("constraint_mode", &"coordinated")
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
	if proposal.operation == &"recommend":
		proposal = proposal.duplicate(true)
		proposal.constraint_mode = &"advisory"
		proposal.tactic = &"flank"
		proposal.required_participants = []
		proposal.assignments = proposal.get("recommendations", []).filter(func(item): return _assignment_for_owner(item.actor_id).is_empty())
		for item: Dictionary in proposal.assignments:
			item.partner_ids = []
			item.beneficiary_id = 0
		if proposal.assignments.is_empty(): return
		proposal.operation = &"extend" if not previous.is_empty() else &"new"
	if proposal.operation == &"keep": return
	if proposal.operation == &"handoff" and not previous.is_empty():
		_install_support_handoff(previous, proposal)
		return
	if proposal.operation == &"none":
		if not previous.is_empty(): _drop_coordination_plan(team_id, StringName(proposal.reason))
		return
	var extending: bool = proposal.operation == &"extend" and not previous.is_empty()
	var revising: bool = proposal.operation == &"revise" and not previous.is_empty()
	var repairing: bool = proposal.operation in [&"repair", &"extend", &"revise"] and not previous.is_empty()
	var plan: Dictionary = previous.duplicate(true) if repairing else {}
	if not repairing:
		plan = {"plan_id": environment.allocate_coordination_id(), "plan_version": 1, "generation": generation, "team_id": team_id,
			"domain": "team:%s" % team_id, "target_id": source.target_id, "evidence_id": source.evidence_id,
			"tactic": proposal.tactic, "phase": &"assigning", "phase_id": 1, "release_at": -1.0,
			"created_at": elapsed, "expires_at": minf(source.valid_until, elapsed + _coordination_plan_duration(proposal)),
			"stage_until": elapsed + COORDINATION_ACCEPT_SECONDS, "assignments": [], "tactical_frame": {}}
		plan.constraint_mode = proposal.get("constraint_mode", &"coordinated")
		if plan.constraint_mode == &"advisory":
			plan.phase = &"executing"
			plan.release_at = elapsed
		plan.posture = proposal.get("posture", &"hold")
		plan.decision = proposal.get("decision", {}).duplicate(true)
		plan.team_config_revision = team_configuration_revision(_context(_coordination_team_members(team_id)[0]))
		if plan.tactic == &"inspect" and _inspection_orders.has(team_id): plan.expires_at = minf(plan.expires_at, _inspection_orders[team_id].expires_at)
		plan.stage_until = minf(plan.stage_until, plan.expires_at)
	elif not extending and not revising:
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
			if not extending and not revising:
				entry.ready_for_phase = false
				# A retained flank has already paid for its completed route segments.
				# Freeze this repair phase's entry at its actual current body instead
				# of asking it to return to the original pre-maneuver starting point.
				if entry.role == &"flank" and entry.accepted and not entry.complete:
					entry.staging_position = _context(entry.actor_id).actor.global_position
			retained.append(entry)
	plan.assignments = retained + new_entries
	if not repairing or revising:
		plan.support_links = proposal.get("support_links", []).duplicate(true)
		for link: Dictionary in plan.support_links:
			link.expires_at = plan.expires_at
			link.revision = int(link.get("revision", 0)) + 1
			for entry: Dictionary in plan.assignments:
				if entry.actor_id == link.beneficiary_id and link.request_id == 0: link.request_id = entry.assignment_id
	elif extending:
		for proposed_link: Dictionary in proposal.get("support_links", []):
			var link := proposed_link.duplicate(true)
			if plan.get("support_links", []).any(func(old): return old.beneficiary_id == link.beneficiary_id): continue
			link.expires_at = plan.expires_at
			link.revision = 1
			for entry: Dictionary in new_entries:
				if entry.actor_id == link.beneficiary_id and link.request_id == 0: link.request_id = entry.assignment_id
			plan.support_links.append(link)
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
		if entry.get("constraint_mode") != &"advisory": environment.store_tactical_reservation(self, _coordination_reservation(_context(entry.actor_id), entry, plan))
	environment.notify_coordination_changed()

func _drop_coordination_plan(team_id: int, _reason: StringName) -> void:
	var plan: Dictionary = _coordination_plans.get(team_id, {})
	if plan.is_empty(): return
	# A successfully checked objective is finished, not a failed layout to
	# retry after its short negative-observation cache expires.
	var order: Dictionary = _inspection_orders.get(team_id, {})
	if _reason == &"complete" and plan.tactic == &"inspect" and order.get("evidence_id") == plan.evidence_id:
		order.slots.clear()
	for entry: Dictionary in plan.assignments:
		environment.release_tactical_reservation(self, entry.reservation_id)
		environment.release_tactical_reservation(self, entry.get("pending_reservation_id", 0))
	_coordination_plans.erase(team_id)
	environment.notify_coordination_changed()

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
		if failure.actor_id == entry.actor_id and failure.get("position_set_key", "") == entry.reserved_position_sets[0] and failure.team_id == plan.team_id and failure.evidence_id == plan.evidence_id and failure.valid_until > elapsed: return
	_coordination_failures.append({"actor_id": entry.actor_id, "position_set_key": entry.reserved_position_sets[0],
		"valid_until": elapsed + 2.0, "team_id": plan.team_id, "target_id": plan.target_id, "evidence_id": plan.evidence_id})
	if _coordination_failures.size() > 128: _coordination_failures.pop_front()

func _install_support_handoff(plan: Dictionary, proposal: Dictionary) -> void:
	if not plan.get("handoff", {}).is_empty(): return
	if proposal.get("handoff", {}).get("existing_replacement", false):
		var existing := _assignment_for_owner(proposal.handoff.replacement_provider_id)
		if existing.is_empty() or not existing.accepted or existing.plan_id != plan.plan_id: return
		plan.handoff = proposal.handoff.duplicate(true)
		var travel := 0.0
		if _context(existing.actor_id).actor.global_position.distance_to(existing.staging_position) > 0.35:
			for offer: Dictionary in existing.raw_offers: travel = maxf(travel, float(offer.travel_seconds))
		plan.handoff.expires_at = minf(plan.expires_at, elapsed + travel + COORDINATION_WAIT_SECONDS)
		environment.notify_coordination_changed()
		return
	if proposal.assignments.size() != 1: return
	var entry := _coordination_entry(proposal.assignments[0], plan)
	if entry.is_empty(): return
	var handoff: Dictionary = proposal.handoff.duplicate(true)
	var travel := 0.0
	for offer: Dictionary in entry.raw_offers: travel = maxf(travel, float(offer.travel_seconds))
	handoff.expires_at = minf(plan.expires_at, elapsed + travel + COORDINATION_WAIT_SECONDS)
	plan.handoff = handoff
	plan.assignments.append(entry)
	environment.store_tactical_reservation(self, _coordination_reservation(_context(entry.actor_id), entry, plan))
	environment.notify_coordination_changed()

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
			environment.notify_coordination_changed()
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
			environment.notify_coordination_changed()
		elif replacement.is_empty() or handoff.expires_at <= elapsed:
			if not handoff.get("existing_replacement", false): _remove_support_assignment(plan, handoff.replacement_provider_id)
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
			# Finishing a finite holding lease is normal. Banning an established
			# post here made every renewal send its occupant elsewhere for 2 s.
			var member = _context(entry.actor_id)
			var held: bool = member != null and entry.accepted and (entry.role == &"front_support" or entry.reserved_offers[0].path_summary.get("holds_position", false)) and member.actor.global_position.distance_to(entry.get("selected_position", Vector3.INF)) <= 0.35
			if not entry.complete and not held: _record_coordination_failure(entry, plan)
		_drop_coordination_plan(plan.team_id, &"expired")
		return
	if plan.get("constraint_mode") == &"advisory":
		# No all-member barrier. Each accepted task reports through the same
		# versioned contract and keeps its original deadline and physical lease.
		for entry: Dictionary in plan.assignments.duplicate():
			if not entry.complete and _coordination_assignment_valid(plan, entry): continue
			environment.release_tactical_reservation(self, entry.reservation_id)
			environment.release_tactical_reservation(self, entry.get("pending_reservation_id", 0))
			plan.assignments.erase(entry)
		if plan.assignments.is_empty(): _drop_coordination_plan(plan.team_id, &"complete")
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
		if entry.role != &"front_support" and not entry.reserved_offers[0].path_summary.get("holds_position", false):
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
		if plan.tactic == &"inspect" and not _inspection_orders.get(plan.team_id, {}).get("slots", {}).is_empty():
			# Whole-party traffic already detects blocked dependencies and owns
			# bounded repair. The old nominal arrival timeout must not cancel a
			# progressing repair. The mission's original fixed expiry still holds.
			plan.stage_until = plan.expires_at
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
		environment.notify_coordination_changed()
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
		_coordination_diagnostics[team_id] = {"at": elapsed, "operation": proposal.operation,
			"reason": proposal.reason, "target_id": source.target_id, "evidence_id": source.evidence_id,
			"member_count": ids.size(), "assigned_count": proposal.assignments.size(),
			"offer_counts": snapshot_value.members.map(func(member): return [member.actor_id, member.offers.size()])}
		_coordination_counters[team_id] = proposal.get("counters", {}).duplicate(true)
		_install_coordination_proposal(team_id, source, proposal)
		_coordination_diagnostics[team_id].assigned_count = _coordination_plans.get(team_id, {}).get("assignments", []).size()

func _advisory_slot_available(context, entry: Dictionary) -> bool:
	if entry.get("constraint_mode") != &"advisory" or entry.accepted: return true
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
		if (other.actor.global_position - anchor).dot(axis) < -FLANK_SIDE_MARGIN or _assignment_for_owner(id).get("accepted", false): owners[id] = true
		elif id != context.actor.get_instance_id() and (other.actor.global_position - anchor).dot(axis) > FLANK_SIDE_MARGIN: front = true
	return front and owners.size() <= floori(float(eligible) / 2.0)

func _context(id: int):
	return _members[id].context.get_ref() if _members.has(id) else null

func _coordination_actual(context, target_id: int) -> Dictionary:
	return environment._coordination_actual(context, target_id)

func _coordination_physical_summary(context, summary: Dictionary, target_id: int) -> Dictionary:
	return environment._coordination_physical_summary(context, summary, target_id)

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

func team_level(context) -> int:
	return environment.team_level(context)

func validate_reservation(context, token: Dictionary) -> bool:
	return environment.validate_reservation(context, token)
