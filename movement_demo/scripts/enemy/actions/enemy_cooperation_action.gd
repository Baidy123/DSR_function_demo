extends "res://scripts/enemy/actions/enemy_action.gd"

const FlankRoute = preload("res://scripts/enemy/services/enemy_flank_route.gd")

## A bounded personal move with an exclusive destination and a public support request.
## Shared services never execute this route or claim that a promise is real protection.
enum Phase { NONE, WAIT_SUPPORT, MOVE, HOLD }
var phase: Phase = Phase.NONE
var destination := Vector3.INF
var _known := Vector3.INF
var _target_id := 0
var _remaining := 0.0
var _waiting := 0.0
var _hold_remaining := 0.0
var _claim: Dictionary = {}
var _had_support := false
var _waypoint := Vector3.INF
var _best_distance := INF
var _stuck := 0.0
var _recheck := 0.0
var _failed_until := 0.0
var _failed_generation := -1
var _route_distance := 0.0
var _route_position := Vector3.INF
var _checkpoints := PackedVector3Array()
var _segment := 0
var _segment_committed := false
var _direct_final := false
var _support_grace := 0.0
var _checkpoint_wait := 0.0
var _coordination_assignment: Dictionary = {}
var _recommendation: Dictionary = {}
var _coordination_offers: Array[Dictionary] = []
var _coordination_local_candidates: Dictionary = {}
var _coordination_complete := false
var _coordination_route_valid := false
var _front_contact_until := -INF

func evaluation_revision() -> int:
	if context == null or context.cooperation == null or context.cooperation.registered_member_count() < 2: return 0
	if _unified_coordinator():
		var source: Dictionary = context.coordination_source(context.cooperation_target_id())
		return hash([source.get("evidence_id", 0), source.get("position", Vector3.INF), source.get("front_axis", Vector3.ZERO), _running])
	return hash([context.cooperation.flank_geometry_revision(context), _running])

func _unified_coordinator() -> bool:
	return context != null and context.cooperation != null and context.has_method("coordination_source") and context.cooperation.has_method("assignment")

func _flank_opportunity() -> Dictionary:
	if not _unified_coordinator(): return context.cooperation.flank_opportunity(context)
	var source: Dictionary = context.coordination_source(context.cooperation_target_id())
	if source.is_empty() or not source.get("flank_clustered", false): return {}
	# This is a geometry frame only. The planner alone determines quotas and owners.
	return {"anchor": source.position, "front_axis": source.front_axis, "round_id": source.evidence_id,
		"capacity": 1, "remaining_slots": 1, "remaining_seconds": maxf(0.0, float(source.valid_until) - context.coordination_now())}

func _move_target() -> Vector3:
	return _checkpoints[_segment] if _segment < _checkpoints.size() else destination

func _personal_advance_allowed(point: Vector3) -> bool:
	if not _unified_coordinator() or not actor.can_use_firearms(): return true
	var source: Dictionary = context.coordination_source(context.cooperation_target_id())
	if source.is_empty(): return true
	# Crossing the frozen front belongs to an assigned flank route. Recheck this
	# at cache consumption and execution too: clustering can change mid-maneuver.
	return (point - source.position).dot(source.front_axis) >= 0.5

func _support_cycle() -> bool:
	for member: Dictionary in _allies():
		if member.get("support_cycle_valid", false) and not member.get("moving", false) and float(member.get("support_resume_seconds", INF)) <= float(_setting(&"support_recovery_seconds", 2.0)): return true
	return false

func _support_continues() -> bool:
	# Recent measured support preserves a short local commitment through ordinary
	# firing gaps. It does not add any fire seconds to candidate scoring.
	return _support_grace > 0.0 or _support_ready() or _support_cycle()

func _evidence() -> Dictionary:
	return context.cooperation_target_evidence()

func _live_evidence(evidence: Dictionary) -> bool:
	return not evidence.is_empty() and evidence.get("position", Vector3.INF).is_finite() and context.evidence_elapsed_seconds < float(evidence.get("valid_until", -INF))

func _allies() -> Array:
	if context.cooperation == null or context.cooperation.registered_member_count() < 2: return []
	var snapshot: Dictionary = context.cooperation_snapshot()
	return snapshot.get("members", []).filter(func(member): return member.get("id", 0) != actor.get_instance_id() and member.get("can_cooperate", false) and member.get("target_id", 0) == context.cooperation_target_id())

func _support_ready(segment_seconds: float = -1.0) -> bool:
	# The public member snapshot is populated from actual fire execution, not claims.
	if segment_seconds < 0.0:
		segment_seconds = context._horizontal_distance(destination) / maxf(0.1, actor.move_speed) if destination.is_finite() else 0.5
	var required := minf(0.1, maxf(0.01, segment_seconds))
	for member: Dictionary in _allies():
		if member.get("ready", false) and not member.get("moving", false) and float(member.get("support_seconds", 0.0)) >= required: return true
	return false

func _fresh_allowed() -> bool:
	if _failed_generation != context.memory_generation:
		_failed_generation = context.memory_generation
		_failed_until = 0.0
	return context.evidence_elapsed_seconds >= _failed_until

func _deployment_enabled() -> bool:
	return context.coordinated_cooperation_enabled() and context.cooperation.has_team_binding(context)

func _deployment_points(known: Vector3) -> Array:
	if not _deployment_enabled(): return []
	var allies := _allies()
	allies.sort_custom(func(a, b): return actor.global_position.distance_squared_to(a.position) < actor.global_position.distance_squared_to(b.position))
	var points: Array = []
	var spacing: float = maxf(1.5, float(_setting(&"deployment_spacing", 2.5)))
	for ally: Dictionary in allies.slice(0, 2):
		var radial: Vector3 = ally.position - known
		radial.y = 0.0
		if radial.is_zero_approx(): continue
		var side := radial.normalized().cross(Vector3.UP)
		for sign_value in [-1.0, 1.0]:
			if actor.global_position.distance_to(ally.position) > spacing * 2.0:
				points.append({"position": ally.position + side * spacing * sign_value, "team_posture": &"concentrate", "ally_id": int(ally.id)})
			points.append({"position": actor.global_position + side * spacing * sign_value, "team_posture": &"disperse", "ally_id": int(ally.id)})
	return points

func evaluation_points() -> Array:
	if _running: return []
	if not is_enabled() or not context.cooperation_enabled() or actor.move_speed <= 0.0 or _allies().is_empty(): return []
	var evidence := _evidence()
	if not _live_evidence(evidence): return []
	var opportunity: Dictionary = _flank_opportunity()
	# Firearms can establish an opposite firing lane. A melee fighter retains
	# its existing covered approach to actual striking distance.
	var arcs: Array = FlankRoute.proposals(context, opportunity) if opportunity.get("capacity", 0) > 0 and actor.can_use_firearms() else []
	var known: Vector3 = evidence.position
	var radial: Vector3 = actor.global_position - known
	radial.y = 0.0
	if radial.length() < 0.5: return []
	var forward := -radial.normalized()
	var side := forward.cross(Vector3.UP)
	var step: float = maxf(0.5, float(_setting(&"flank_distance", 3.0)))
	var points: Array = []
	# These are finite local proposals, not a synchronous map search.
	for sign_value in [-1.0, 1.0]:
		var lateral: Vector3 = actor.global_position + side * step * sign_value
		points.append({"position": lateral})
		points.append({"position": lateral + forward * minf(step * 0.5, radial.length() * 0.25)})
		var angle: float = deg_to_rad(clampf(float(_setting(&"flank_angle_degrees", 60.0)), 0.0, 90.0)) * sign_value
		var offset: Vector3 = radial.rotated(Vector3.UP, angle) - radial
		points.append({"position": actor.global_position + offset.limit_length(step)})
	if not actor.can_use_firearms():
		points.append({"position": actor.global_position + forward * minf(step, maxf(0.0, radial.length() - 1.0))})
	# Existing cover samples keep their ownership and clearance checks.
	var nearby: Array = context.spatial.regions()
	nearby.sort_custom(func(a, b): return actor.global_position.distance_squared_to(a.global_position) < actor.global_position.distance_squared_to(b.global_position))
	for region in nearby.slice(0, 2):
		for cell: Dictionary in region.get_attack_cells():
			if actor.global_position.distance_to(cell.position) <= step * 1.5: points.append(cell)
	if opportunity.get("capacity", 0) > 0:
		points = points.filter(func(point): return (point.position - opportunity.anchor).dot(opportunity.front_axis) >= -0.5)
	points = points.filter(func(point): return _personal_advance_allowed(point.position))
	var deployment := _deployment_points(known)
	return arcs.slice(0, 2) + deployment.slice(0, 2) + arcs.slice(2) + deployment.slice(2) + points

func evaluation_weight() -> int:
	return 2

func evaluation_priority_count() -> int:
	return 4

func _angle_gain(point: Vector3, known: Vector3) -> float:
	var minimum: float = deg_to_rad(maxf(1.0, float(_setting(&"minimum_angle_degrees", 25.0))))
	var from_target: Vector3 = point - known
	var current: Vector3 = actor.global_position - known
	from_target.y = 0.0
	current.y = 0.0
	if from_target.is_zero_approx() or current.is_zero_approx(): return 0.0
	var best := 0.0
	for member: Dictionary in _allies():
		var other: Vector3 = member.position - known
		other.y = 0.0
		if other.is_zero_approx(): continue
		var separation: float = other.angle_to(from_target)
		var established: float = other.angle_to(current)
		if established >= deg_to_rad(maxf(rad_to_deg(minimum), float(_setting(&"flank_angle_degrees", 60.0)))): continue
		var added: float = separation - established
		if added >= minimum * 0.5 and separation >= minimum:
			best = maxf(best, clampf(added / maxf(minimum, deg_to_rad(90.0)), 0.0, 1.0))
	return best

func evaluate_point(point: Variant) -> Dictionary:
	var evidence := _evidence()
	if not _live_evidence(evidence) or _allies().is_empty(): return {}
	if point.has("checkpoints"): return _assess_flank(point)
	var known: Vector3 = evidence.position
	var position: Vector3 = point.get("position", Vector3.INF)
	if not _personal_advance_allowed(position): return {}
	if not position.is_finite() or actor.global_position.distance_to(position) < 0.5 or not context.is_position_free(position): return {}
	if context.is_utility_destination_blocked(position): return {}
	var path: PackedVector3Array = selection._path_to(actor.global_position, position)
	if path.is_empty(): return {}
	if point.has("team_posture") and not FlankRoute.safe_path(path, known): return {}
	var quality := _angle_gain(position, known)
	if point.get("team_posture") == &"concentrate":
		for ally: Dictionary in _allies():
			if ally.id == point.get("ally_id"):
				var original: float = actor.global_position.distance_to(ally.position)
				quality = maxf(quality, clampf((original - position.distance_to(ally.position)) / maxf(1.0, original), 0.0, 1.0))
	if not actor.can_use_firearms():
		var progress: float = actor.global_position.distance_to(known) - position.distance_to(known)
		if progress > 0.5: quality = maxf(quality, clampf(progress / maxf(0.5, float(_setting(&"flank_distance", 3.0))), 0.0, 1.0))
	if quality <= 0.0: return {}
	var target: Vector3 = context.known_target_point(known)
	var fire_quality := 0.0
	var protection := -1.0
	var movement_qualified := false
	if actor.can_use_firearms():
		if actor.weapon == null or position.distance_to(known) > minf(actor.weapon.fire_range, maxf(context.perception.sight_distance, context.perception.close_awareness_radius)): return {}
		var origin: Vector3 = actor.get_posture_muzzle_position(false, position)
		if point.get("body") != null:
			if not is_instance_valid(point.body): return {}
			if point.body.is_low_cover():
				target = selection.low_cover_attack_target(position, context.known_target_points(known))
				if not target.is_finite(): return {}
			var checked: Dictionary = selection.assess_attack_point(position, point.body, target, target, false)
			if not checked.usable: return {}
			protection = checked.protection
			fire_quality = checked.fire_quality
		else:
			if not context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)): return {}
			fire_quality = context.fire.firing_lane_quality(origin, target - origin, origin.distance_to(target))
		movement_qualified = fire_quality > 0.0
	elif actor.weapon != null and actor.weapon.melee_enabled:
		var approach: Vector3 = known - position
		movement_qualified = Vector2(approach.x, approach.z).length() <= maxf(0.1, actor.weapon.melee_range) and absf(approach.y) <= actor.weapon.melee_height_tolerance
		movement_qualified = movement_qualified and selection.has_clear_line(position + Vector3.UP * 0.8, known + Vector3.UP * 0.8)
	var route: Dictionary = context.spatial.assess_route(context, path, known, 1.0, context.spatial._reload_seconds(context), context.sees_player)
	var horizon: float = context.utility_horizon_seconds
	var wait: float = 0.0 if point.has("team_posture") or context.cooperation_level() == 1 or _support_ready(route.seconds) else maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
	var arrival: float = route.seconds + wait
	var available: float = maxf(0.0, horizon - arrival)
	if actor.can_use_firearms(): available = maxf(0.0, horizon - maxf(arrival, context.spatial._ammo_wait(context)))
	var exposure: float = route.exposure + context._reload_exposure(actor.global_position, known) * wait + context._reload_exposure(position, known, protection) * available
	var unavailable: float = maxf(route.seconds - route.fire_seconds + wait, context.spatial._ammo_wait(context)) + available * (1.0 - fire_quality)
	if not actor.can_use_firearms():
		unavailable = minf(horizon, arrival + maxf(0.0, position.distance_to(known) - 1.0) / maxf(0.1, actor.move_speed))
	var lane := "position:%d:%d" % [roundi(position.x / 0.8), roundi(position.z / 0.8)]
	var cooperation := {"target_id": context.cooperation_target_id(), "kind": &"advance", "lane_id": lane,
		"position": position, "beneficiary_id": actor.get_instance_id(), "request_id": 0,
		"support_seconds": available, "estimated_start_seconds": arrival, "quality": quality,
		"movement_start_seconds": wait, "movement_seconds": route.seconds, "movement_qualified": movement_qualified}
	var result := {"destination": {"position": position, "path": path}, "unavailable": unavailable, "exposed": exposure,
		"information": minf(horizon, arrival) if not context.sees_player else 0.0, "cooperation": cooperation,
		"cost": context.spatial.score(unavailable, exposure, minf(horizon, arrival) if not context.sees_player else 0.0)}
	if point.get("body") != null: result.destination.body = point.body
	if point.has("team_posture"):
		result.destination.team_posture = point.team_posture
		result.destination.ally_id = point.get("ally_id", 0)
		result.destination.route_seconds = route.seconds
		result.destination.checkpoints = FlankRoute._short_checkpoints(path)
	return result

func _assess_flank(point: Dictionary, continuing: bool = false) -> Dictionary:
	if not actor.can_use_firearms() and (actor.weapon == null or not actor.weapon.melee_enabled): return {}
	var destination_data: Dictionary = point if continuing else FlankRoute.assess(context, point)
	if destination_data.is_empty(): return {}
	if float(destination_data.get("route_seconds", INF)) > float(_setting(&"flank_plan_seconds", 14.0)) - 1.0: return {}
	if not continuing:
		var opportunity: Dictionary = _flank_opportunity()
		if float(destination_data.route_seconds) > float(opportunity.get("remaining_seconds", _setting(&"flank_plan_seconds", 14.0))) - 1.0: return {}
	var known: Vector3 = destination_data.flank_anchor
	var position: Vector3 = destination_data.position
	if context.is_utility_destination_blocked(position): return {}
	var fire_quality := 0.0
	if actor.can_use_firearms():
		if actor.weapon == null or position.distance_to(known) > minf(actor.weapon.fire_range, maxf(context.perception.sight_distance, context.perception.close_awareness_radius)): return {}
		var origin: Vector3 = actor.get_posture_muzzle_position(false, position)
		var target: Vector3 = context.known_target_point(known)
		if not context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)): return {}
		fire_quality = context.fire.firing_lane_quality(origin, target - origin, origin.distance_to(target))
	var path: PackedVector3Array = destination_data.path
	var route: Dictionary = context.spatial.assess_route(context, path, known, 1.0, context.spatial._reload_seconds(context), context.sees_player)
	var wait := 0.0 if context.cooperation_level() == 1 or _support_ready(route.seconds) else maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
	if continuing:
		if phase == Phase.MOVE and (_segment_committed or _support_continues()): wait = 0.0
		elif phase == Phase.WAIT_SUPPORT: wait = _waiting
		elif context.cooperation_level() != 1 and not _support_ready(): wait = _checkpoint_wait
	var horizon: float = context.utility_horizon_seconds
	# Evaluate only the next checkpoint. There is no arrival-fire credit at the
	# final position until it is actually reachable within this decision segment.
	var travel: float = route.seconds
	var stationary: float = maxf(0.0, horizon - travel - wait)
	var endpoint: Vector3 = path[-1]
	var unavailable: float = minf(horizon, travel - route.fire_seconds + wait)
	var end_quality := 0.0
	if actor.can_use_firearms():
		var origin: Vector3 = actor.get_posture_muzzle_position(false, endpoint)
		var target: Vector3 = context.known_target_point(known)
		end_quality = context.fire.firing_lane_quality(origin, target - origin, origin.distance_to(target)) if origin.distance_to(target) <= actor.weapon.fire_range and context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)) else 0.0
		unavailable = maxf(unavailable + stationary * (1.0 - end_quality), context.spatial._ammo_wait(context))
	else:
		var offset: Vector3 = known - endpoint
		var reachable: bool = Vector2(offset.x, offset.z).length() <= actor.weapon.melee_range and absf(offset.y) <= actor.weapon.melee_height_tolerance
		reachable = reachable and selection.has_clear_line(endpoint + Vector3.UP * 0.8, known + Vector3.UP * 0.8)
		unavailable = minf(horizon, travel + wait) if reachable else horizon
	var start_exposure: float = context._reload_exposure(actor.global_position, known)
	var end_exposure: float = context._reload_exposure(endpoint, known)
	var exposed: float = route.exposure + start_exposure * wait + end_exposure * stationary
	var task := {"target_id": context.cooperation_target_id(), "kind": &"flank", "lane_id": "position:%d:%d" % [roundi(position.x / 0.8), roundi(position.z / 0.8)],
		"position": position, "beneficiary_id": actor.get_instance_id(), "request_id": 0,
		"support_seconds": 0.0, "estimated_start_seconds": horizon, "quality": 1.0,
		"movement_start_seconds": wait, "movement_seconds": travel, "movement_qualified": fire_quality > 0.0 or (not actor.can_use_firearms() and position.distance_to(known) < actor.global_position.distance_to(known) - 0.5),
		"flank_anchor": known, "flank_axis": destination_data.flank_axis, "flank_round_id": destination_data.flank_round_id, "flank_destination": position}
	var information := _flank_information(endpoint, travel + wait)
	return {"destination": destination_data, "unavailable": unavailable, "exposed": exposed, "information": information,
		"cooperation": task, "cost": context.spatial.score(unavailable, exposed, information),
		"timing": {"route_unavailable": travel - route.fire_seconds, "route_exposure": route.exposure,
			"start_exposure": start_exposure, "end_exposure": end_exposure, "end_quality": end_quality}}

func _fresh_flank_candidate(assessment: Dictionary) -> Dictionary:
	var candidate := _candidate(assessment)
	var timing: Dictionary = assessment.get("timing", {})
	if timing.is_empty() or not actor.can_use_firearms(): return candidate
	# Spatial caches retain geometry, never an old observation of whether a
	# partner is currently ready. Reprice that small time window at selection.
	var travel: float = candidate.cooperation.movement_seconds
	var wait: float = 0.0 if context.cooperation_level() == 1 or _support_ready(travel) else maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
	var horizon: float = context.utility_horizon_seconds
	var stationary: float = maxf(0.0, horizon - travel - wait)
	candidate.outcome.unavailable_seconds = maxf(minf(horizon, timing.route_unavailable + wait) + stationary * (1.0 - timing.end_quality), context.spatial._ammo_wait(context))
	candidate.outcome.exposed_seconds = timing.route_exposure + timing.start_exposure * wait + timing.end_exposure * stationary
	candidate.outcome.information_loss = _flank_information(assessment.destination.path[-1], travel + wait)
	candidate.cooperation.movement_start_seconds = wait
	return candidate

func _flank_information(endpoint: Vector3, arrival_seconds: float) -> float:
	if context.sees_player: return 0.0
	var report: Dictionary = context.fresh_shared_contact()
	if not report.is_empty(): return context.shared_contact_information(endpoint, arrival_seconds, report)
	return minf(context.utility_horizon_seconds, arrival_seconds)

func _candidate(assessment: Dictionary) -> Dictionary:
	var candidate := option(assessment.destination, assessment.unavailable, assessment.exposed, assessment.information, &"advance")
	candidate.cooperation = assessment.cooperation.duplicate(true)
	candidate.target_id = context.cooperation_target_id()
	candidate.known_position = _evidence().get("position", Vector3.INF)
	if assessment.cooperation.kind == &"flank":
		candidate.plan = &"opposite_flank"
		candidate.segment_index = _segment if _running else 0
	return candidate

func _slot_available(task: Dictionary) -> bool:
	if _unified_coordinator(): return true
	if task.get("kind", &"") == &"flank":
		if _running and not _claim.is_empty(): return true
		var opportunity: Dictionary = context.cooperation.flank_opportunity(context)
		if int(opportunity.get("remaining_slots", 0)) <= 0 or opportunity.anchor.distance_to(task.get("flank_anchor", Vector3.INF)) > 0.1 or opportunity.front_axis.distance_to(task.get("flank_axis", Vector3.ZERO)) > 0.01: return false
		for claim: Dictionary in context.cooperation_snapshot().get("claims", []):
			if claim.kind == &"flank" and claim.owner_id != actor.get_instance_id() and claim.flank_destination.distance_to(task.flank_destination) < 1.2: return false
		return true
	for claim: Dictionary in context.cooperation_snapshot(task.get("target_id", 0)).get("claims", []):
		if claim.get("owner_id", 0) != actor.get_instance_id() and claim.get("kind", &"") == &"advance" and String(claim.get("lane_id", "")) == String(task.get("lane_id", "")): return false
	return true

func expand_route_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	# This action measures strict walking routes. A vault needs its own timing and
	# support gate; the shared route expander must not copy walking credit to it.
	var result: Array[Dictionary] = []
	for candidate in candidates:
		if candidate.get("route", {}).is_empty(): result.append(candidate)
	return result

func collect_candidates(_visible: bool) -> Array[Dictionary]:
	_coordination_offers.clear()
	var result: Array[Dictionary] = []
	if not is_enabled() or not context.cooperation_enabled() or actor.move_speed <= 0.0: return result
	if actor.can_use_firearms() and actor.ammo.magazine_rounds <= 0 and not actor.ammo.is_reloading: return result
	if not _recommendation.is_empty():
		if _recommended_valid(): result.append(_coordinated_candidate())
		return result
	if not _coordination_assignment.is_empty():
		if _coordinated_valid(_visible): result.append(_coordinated_candidate())
		return result
	if _unified_coordinator():
		var assigned: Dictionary = context.coordination_assignment()
		if context.cooperation_level() == 1: assigned = context.coordination_recommendation()
		if assigned.get("owner_action", &"") == action_id:
			for key in assigned.get("allowed_offer_keys", []):
				if _coordination_local_candidates.has(key): result.append(_coordination_local_candidates[key].duplicate(true))
			return result
	if _running:
		if valid(context.sees_player):
			if not _checkpoints.is_empty() and phase != Phase.HOLD:
				var current_destination: Dictionary = plan.destination.duplicate(true)
				current_destination.path = selection._path_to(actor.global_position, _move_target())
				if not FlankRoute.safe_path(current_destination.path, _known): return result
				var current_assessment := _assess_flank(current_destination, true)
				if not current_assessment.is_empty(): result.append(_candidate(current_assessment))
				return result
			var continuing := plan.duplicate(true)
			var moving_seconds: float = maxf(_route_distance, context._horizontal_distance(destination)) / maxf(0.1, actor.move_speed) if phase != Phase.HOLD else 0.0
			var wait: float = _waiting if phase == Phase.WAIT_SUPPORT else 0.0
			continuing.cooperation.movement_start_seconds = wait
			continuing.cooperation.movement_seconds = minf(moving_seconds, maxf(0.0, _remaining - wait))
			continuing.cooperation.estimated_start_seconds = wait + moving_seconds
			continuing.cooperation.support_seconds = minf(float(continuing.cooperation.get("support_seconds", 0.0)), _remaining)
			# Costs already paid while reaching this point must not be paid again.
			var unavailable: float = minf(context.utility_horizon_seconds, moving_seconds + wait)
			continuing.outcome.unavailable_seconds = unavailable
			continuing.outcome.exposed_seconds = context._reload_exposure(actor.global_position, _known) * context.utility_horizon_seconds
			continuing.outcome.information_loss = 0.0 if context.sees_player else minf(context.utility_horizon_seconds, moving_seconds + wait)
			if phase == Phase.HOLD:
				var prediction := _hold_support_prediction(minf(_remaining, _hold_remaining))
				continuing.cooperation.estimated_start_seconds = prediction.estimated_start_seconds
				continuing.cooperation.support_seconds = prediction.support_seconds
				continuing.outcome.unavailable_seconds = minf(context.utility_horizon_seconds, prediction.estimated_start_seconds)
			elif actor.can_use_firearms():
				continuing.outcome.unavailable_seconds = maxf(float(continuing.outcome.unavailable_seconds), context.spatial._ammo_wait(context))
				continuing.cooperation.support_seconds = minf(float(continuing.cooperation.support_seconds), maxf(0.0, context.utility_horizon_seconds - context.spatial._ammo_wait(context)))
			result.append(continuing)
		return result
	if not _fresh_allowed() or not _live_evidence(_evidence()) or _allies().is_empty(): return result
	var covering := _overwatch_candidate()
	if not covering.is_empty(): result.append(covering)
	var source: Dictionary = context.coordination_source(context.cooperation_target_id()) if _unified_coordinator() else {}
	if not source.is_empty():
		var front := _front_candidate(source)
		if not front.is_empty(): result.append(front)
	var flanks: Array[Dictionary] = []
	var advances: Array[Dictionary] = []
	for assessment: Dictionary in context.spatial.assessments(self):
		if assessment.is_empty() or not _slot_available(assessment.cooperation): continue
		var candidate := _fresh_flank_candidate(assessment)
		if assessment.cooperation.kind == &"flank":
			if not _unified_coordinator() or _attach_tactical_offer(candidate, source, &"flank"): flanks.append(candidate)
		elif candidate.destination.has("team_posture") and _deployment_enabled():
			if _attach_tactical_offer(candidate, source, &"team_position"): result.append(candidate)
			if actor.can_use_firearms() and not actor.ammo.is_reloading and actor.ammo.magazine_rounds > 0:
				var support_position := candidate.duplicate(true)
				if _attach_tactical_offer(support_position, source, &"front_support"): result.append(support_position)
		else:
			# A personal advance cannot manufacture a covering shooter by waiting.
			# Keep prepared geometry, but publish movement only with actual fire or
			# its measured bounded recovery. Otherwise personal search can proceed.
			if context.cooperation_level() != 1 and _personal_advance_allowed(candidate.destination.position) and (_support_ready(0.1) or _support_cycle()): advances.append(candidate)
	# Local movement remains a personal option even while tactical offers exist.
	result.append_array(flanks)
	result.append_array(advances)
	return result

func _overwatch_candidate() -> Dictionary:
	if not context.coordinated_cooperation_enabled(): return {}
	if not context.sees_player or not actor.can_use_firearms() or actor.ammo.is_reloading or actor.ammo.magazine_rounds <= 0: return {}
	var requests: Array = context.cooperation_snapshot().get("requests", [])
	if requests.is_empty(): return {}
	var duration := maxf(float(_setting(&"lane_hold_seconds", 1.2)), context.fire.support_burst_duration())
	if _running and phase == Phase.HOLD:
		duration = minf(_remaining, _hold_remaining)
	var prediction := _hold_support_prediction(duration)
	if prediction.support_seconds <= 0.0: return {}
	for request: Dictionary in requests:
		if request.beneficiary_id == actor.get_instance_id() or request.get("lane_id", &"target") != &"target": continue
		var wait: float = prediction.estimated_start_seconds
		var support: float = minf(prediction.support_seconds, maxf(0.0, float(request.get("remaining", 0.0)) - wait))
		if support <= 0.0: continue
		var candidate := option({}, wait, context._reload_exposure(actor.global_position, context.last_known_position) * context.utility_horizon_seconds, 0.0, &"overwatch")
		candidate.target_id = context.cooperation_target_id()
		candidate.known_position = _evidence().position
		candidate.hold_seconds = minf(duration, float(request.get("remaining", 0.0)))
		candidate.cooperation = {"kind": &"support", "target_id": candidate.target_id, "position": actor.global_position,
			"lane_id": &"target", "request_id": request.request_id, "beneficiary_id": request.beneficiary_id,
			"support_seconds": support, "estimated_start_seconds": wait, "quality": 1.0,
			"movement_start_seconds": 0.0, "movement_seconds": 0.0, "movement_qualified": false}
		return candidate
	return {}

## A hold promises only its own remaining life. Re-evaluation cannot borrow a
## later action's shots or claim that an unaligned/blocked gun is already useful.
func _hold_support_prediction(duration: float) -> Dictionary:
	var horizon: float = context.utility_horizon_seconds
	var result := {"estimated_start_seconds": horizon, "support_seconds": 0.0}
	if duration <= 0.0 or not context.sees_player or not actor.can_use_firearms() or actor.ammo.is_reloading or actor.ammo.magazine_rounds <= 0: return result
	if actor.is_vaulting() or actor.melee_active or not actor.has_aim or not actor.aim_acquired: return result
	if not context.perception.can_see_player(): return result
	var target: Vector3 = context.last_seen_aim_position
	if not target.is_finite(): return result
	var origin: Vector3 = actor.get_shot_origin()
	var desired: Vector3 = target - origin
	if desired.is_zero_approx() or desired.length() > actor.weapon.fire_range or actor.aim_direction.angle_to(desired) > actor.AIM_ACQUIRE_ANGLE: return result
	var horizontal_aim := Vector3(actor.aim_direction.x, 0.0, actor.aim_direction.z)
	var forward := Vector3(-actor.global_basis.z.x, 0.0, -actor.global_basis.z.z)
	if not horizontal_aim.is_zero_approx() and forward.angle_to(horizontal_aim) > actor.MAX_GUN_BODY_ANGLE: return result
	if not context.fire.has_clear_firing_lane(origin, desired, desired.length()) or not context.cooperation_line_safe(origin, target): return result
	if not actor.aim_direction.is_equal_approx(desired.normalized()) and not context.fire.has_clear_firing_lane(origin, actor.aim_direction, desired.length()): return result
	var delay: float = maxf(context.fire.fire_pause_remaining, maxf(context.fire.shot_wait_seconds(), maxf(0.0, context.fire.fire_reaction_seconds - context.fire.fire_reaction_elapsed)))
	delay += context.fire.estimated_steady_wait(true)
	result.estimated_start_seconds = delay
	result.support_seconds = minf(context.fire.burst_window_seconds(true), maxf(0.0, minf(horizon, duration) - delay))
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	if candidate.has("coordination_recommendation"): return _validate_recommended(candidate)
	if candidate.has("coordination_role"): return _validate_coordinated(candidate, visible)
	if _unified_coordinator() and candidate.get("cooperation", {}).get("kind") == &"flank": return false
	if not candidate.get("route", {}).is_empty(): return false
	if not is_enabled() or not context.cooperation_enabled() or candidate.get("target_id", 0) != context.cooperation_target_id(): return false
	if not _live_evidence(_evidence()): return false
	if candidate.get("plan", &"") == &"overwatch": return not _overwatch_candidate().is_empty()
	if not candidate.get("destination", {}).has("checkpoints") and not _personal_advance_allowed(candidate.get("destination", {}).get("position", Vector3.INF)): return false
	if not candidate.get("destination", {}).has("checkpoints") and not super.validate(candidate, visible): return false
	if not _slot_available(candidate.get("cooperation", {})): return false
	if _running and candidate.get("destination", {}).get("position", Vector3.INF).is_equal_approx(destination): return true
	return not evaluate_point(candidate.destination).is_empty()

func begin(candidate: Dictionary, visible: bool) -> bool:
	if candidate.has("coordination_recommendation"): return _begin_recommended(candidate, visible)
	if candidate.has("coordination_role"): return _begin_coordinated(candidate, visible)
	if not validate(candidate, visible): return false
	var task: Dictionary = candidate.cooperation.duplicate(true)
	task.owner_action = action_id
	task.duration = maxf(0.1, float(_setting(&"plan_seconds", 4.0))) + maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
	if task.kind == &"flank": task.duration = maxf(4.0, float(_setting(&"flank_plan_seconds", 14.0)))
	var claimed: Dictionary = context.cooperation_claim(task)
	if claimed.is_empty(): return false
	reset()
	_claim = claimed
	super.begin(candidate, visible)
	if candidate.get("plan", &"") == &"overwatch":
		destination = actor.global_position
		_known = candidate.known_position
		_target_id = candidate.target_id
		_remaining = task.duration
		_hold_remaining = minf(task.duration, maxf(0.0, float(candidate.get("hold_seconds", _setting(&"lane_hold_seconds", 1.2)))))
		phase = Phase.HOLD
		actor.agent.target_position = actor.global_position
		return true
	destination = candidate.destination.position
	_checkpoints = candidate.destination.get("checkpoints", PackedVector3Array())
	_segment_committed = true
	_route_distance = selection._path_length_from_path(candidate.destination.path)
	_route_position = actor.global_position
	_known = candidate.known_position
	_target_id = candidate.target_id
	_remaining = minf(task.duration, float(claimed.expires_at) - context.cooperation.elapsed)
	_waiting = maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
	_had_support = _support_ready()
	_support_grace = float(_setting(&"support_recovery_seconds", 2.0)) if _had_support else 0.0
	phase = Phase.MOVE if _had_support else Phase.WAIT_SUPPORT
	actor.agent.target_position = _move_target() if phase == Phase.MOVE else actor.global_position
	return true

func valid(_visible: bool) -> bool:
	if not _recommendation.is_empty(): return _recommended_valid()
	if not _coordination_assignment.is_empty(): return _coordinated_valid(_visible)
	if not _running or phase == Phase.NONE or not is_enabled() or not context.cooperation_enabled(): return false
	if _checkpoints.is_empty() and plan.get("plan", &"") != &"overwatch" and not _personal_advance_allowed(destination): return false
	if actor.can_use_firearms() and actor.ammo.magazine_rounds <= 0 and not actor.ammo.is_reloading: return false
	var evidence := _evidence()
	return _remaining > 0.0 and _target_id == context.cooperation_target_id() and _live_evidence(evidence) and evidence.position.distance_to(_known) <= 2.0

func _fire(visible: bool) -> Dictionary:
	return {"owner": action_id, "mode": &"visible", "support_intent": phase == Phase.HOLD and context.coordinated_cooperation_enabled()} if visible and actor.can_use_firearms() else {}

func can_interrupt(_next: Dictionary, _visible: bool) -> bool:
	# A short leg is atomic; Utility is consulted again at every checkpoint.
	if _recommendation.is_empty() and not _checkpoints.is_empty() and not _segment_committed and not _support_continues() and _checkpoint_wait > 0.0 and valid(_visible): return false
	return _checkpoints.is_empty() or not _segment_committed or phase == Phase.HOLD or not valid(_visible)

func tick(delta: float, visible: bool) -> Dictionary:
	if not _coordination_assignment.is_empty(): return _tick_coordinated(delta, visible)
	_remaining = maxf(0.0, _remaining - maxf(0.0, delta))
	_support_grace = float(_setting(&"support_recovery_seconds", 2.0)) if _support_ready() else maxf(0.0, _support_grace - delta)
	if not valid(visible) or (_recommendation.is_empty() and not context.cooperation_update(_claim, {"phase": phase, "position": actor.global_position})):
		_finish(false)
		return motion(Vector3.ZERO)
	if phase == Phase.WAIT_SUPPORT:
		_waiting = maxf(0.0, _waiting - delta)
		if _support_ready():
			_had_support = true
			phase = Phase.MOVE
			actor.agent.target_position = _move_target()
		elif _waiting <= 0.0:
			_finish(true)
		context.state = context.State.HOLD_POSITION
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible) if _running else {})
	if phase == Phase.HOLD:
		_hold_remaining = maxf(0.0, _hold_remaining - delta)
		if _hold_remaining <= 0.0 or not visible: _finish(false)
		context.state = context.State.HOLD_POSITION
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible) if _running else {})
	var target := _move_target()
	var distance: float = context._horizontal_distance(target)
	if not _checkpoints.is_empty() and not _segment_committed:
		_checkpoint_wait = maxf(0.0, _checkpoint_wait - delta)
		if (_recommendation.is_empty() and not _support_continues()) or int(plan.get("segment_index", -1)) != _segment:
			if _checkpoint_wait <= 0.0: _finish(false)
			return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible))
		_segment_committed = true
	if _route_position.is_finite():
		var travelled: Vector3 = actor.global_position - _route_position
		_route_distance = maxf(0.0, _route_distance - Vector2(travelled.x, travelled.z).length())
	_route_position = actor.global_position
	# Losing support far from the destination returns the current position to Utility.
	# A nearly completed segment can still reach its previously checked safe point.
	if _recommendation.is_empty() and _had_support and _support_grace <= 0.0 and not _support_cycle() and distance > 1.5:
		_finish(false)
		return motion(Vector3.ZERO)
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.25
		var path: PackedVector3Array = selection._path_to(actor.global_position, target)
		if not context.is_position_free(target) or path.is_empty() or (not _checkpoints.is_empty() and not FlankRoute.safe_path(path, _known)):
			_finish(true)
			return motion(Vector3.ZERO)
		_route_distance = selection._path_length_from_path(path)
		_direct_final = _route_distance <= actor.global_position.distance_to(target) + 0.08
	if distance <= 0.15:
		if _segment + 1 < _checkpoints.size():
			_segment += 1
			_segment_committed = false
			_checkpoint_wait = float(_setting(&"support_recovery_seconds", 2.0))
			_recheck = 0.0
			_stuck = 0.0
			actor.agent.target_position = actor.global_position
			context.invalidate_utility()
			return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible))
		if not visible or not actor.can_use_firearms():
			_finish(false)
			return motion(Vector3.ZERO)
		phase = Phase.HOLD
		_hold_remaining = maxf(0.1, float(_setting(&"lane_hold_seconds", 1.2)))
		actor.agent.target_position = actor.global_position
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible))
	actor.agent.target_position = target
	var next: Vector3 = actor.agent.get_next_path_position()
	if distance <= 0.7 and _direct_final: next = target
	if actor.agent.is_navigation_finished() and distance > 0.7:
		_finish(true)
		return motion(Vector3.ZERO)
	var waypoint_distance: float = context._horizontal_distance(next)
	if not _waypoint.is_finite() or _waypoint.distance_to(next) > 0.25:
		_waypoint = next
		_best_distance = INF
	if waypoint_distance < _best_distance - 0.04:
		_best_distance = waypoint_distance
		_stuck = 0.0
	else: _stuck += delta
	if _stuck >= 1.5:
		_finish(true)
		return motion(Vector3.ZERO)
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	context.state = context.State.REPOSITION
	return motion(direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * delta)), 1.0, _known - actor.global_position, _fire(visible))

func route_tick(_delta: float, _visible: bool) -> Dictionary:
	# Fail closed if an obsolete/external route bypassed the walking-only entry.
	# execute_tick sees _running=false and cannot apply a vault to the body.
	_finish(false)
	return motion(Vector3.ZERO)

func _finish(failed: bool) -> void:
	if failed and destination.is_finite(): context.block_utility_destination(destination)
	_failed_until = context.evidence_elapsed_seconds + maxf(0.1, float(_setting(&"wait_seconds", 1.2)))
	reset()
	_running = false

func reset() -> void:
	if not _claim.is_empty() and context != null: context.cooperation_release(_claim)
	_claim = {}
	phase = Phase.NONE
	destination = Vector3.INF
	_known = Vector3.INF
	_remaining = 0.0
	_waiting = 0.0
	_hold_remaining = 0.0
	_had_support = false
	_waypoint = Vector3.INF
	_best_distance = INF
	_stuck = 0.0
	_recheck = 0.0
	_route_distance = 0.0
	_route_position = Vector3.INF
	_checkpoints.clear()
	_segment = 0
	_segment_committed = false
	_direct_final = false
	_support_grace = 0.0
	_checkpoint_wait = 0.0
	_coordination_assignment = {}
	_recommendation = {}
	_coordination_complete = false
	_coordination_route_valid = false
	_front_contact_until = -INF

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running: _finish(false)

func state_label() -> String:
	if _running and plan.get("coordination_role") == &"team_position": return "集中支援" if plan.destination.get("team_posture") == &"concentrate" else "展开射界"
	if _running and plan.get("coordination_role") == &"front_support" and phase == Phase.MOVE: return "接近支援位置"
	if _running and plan.get("coordination_role") == &"front_support": return "正面掩护"
	if _running and plan.get("plan", &"") == &"overwatch": return "掩护队友"
	if _running and not _checkpoints.is_empty():
		if phase == Phase.HOLD: return "保持侧后射界"
		if _recommendation.is_empty() and (phase == Phase.WAIT_SUPPORT or not _segment_committed): return "包抄途中等待掩护"
		return "绕行包抄 %d/%d" % [_segment + 1, _checkpoints.size()]
	return ["", "等待友军掩护", "协同侧向推进", "保持交叉火力"][phase]


func coordination_offers(_visible: bool) -> Array[Dictionary]:
	return _coordination_offers.duplicate(true) if _unified_coordinator() and context.cooperation_enabled() and context.cooperation.registered_member_count() > 1 else []

func _own_actual_support() -> Dictionary:
	for member: Dictionary in context.cooperation_snapshot().get("members", []):
		if member.get("id", 0) == actor.get_instance_id() and member.get("target_id", 0) == context.cooperation_target_id():
			return {"ready": member.get("ready", false) and not member.get("moving", false), "seconds": maxf(0.0, float(member.get("support_seconds", 0.0)))}
	return {"ready": false, "seconds": 0.0}

func _front_candidate(source: Dictionary) -> Dictionary:
	if not context.sees_player or not actor.can_use_firearms() or actor.is_vaulting() or actor.melee_active: return {}
	var duration: float = minf(float(_setting(&"flank_plan_seconds", 14.0)), float(source.valid_until) - context.coordination_now())
	var prediction := _hold_support_prediction(duration)
	if prediction.support_seconds <= 0.0: return {}
	var actual := _own_actual_support()
	if not _deployment_enabled() and (not actual.ready or actual.seconds <= 0.0): return {}
	var candidate := option({"position": actor.global_position}, prediction.estimated_start_seconds, context._reload_exposure(actor.global_position, source.position) * context.utility_horizon_seconds, 0.0, &"front_support")
	candidate.target_id = source.target_id
	candidate.known_position = source.position
	candidate.hold_seconds = duration
	candidate.cooperation = {"kind": &"support", "target_id": source.target_id, "position": actor.global_position,
		"lane_id": &"target", "request_id": 0, "beneficiary_id": actor.get_instance_id(),
		"support_seconds": prediction.support_seconds if _deployment_enabled() else minf(prediction.support_seconds, actual.seconds), "estimated_start_seconds": prediction.estimated_start_seconds,
		"quality": 1.0, "movement_start_seconds": 0.0, "movement_seconds": 0.0, "movement_qualified": false}
	return candidate if _attach_tactical_offer(candidate, source, &"front_support") else {}

func _attach_tactical_offer(candidate: Dictionary, source: Dictionary, role: StringName) -> bool:
	if source.is_empty() or not context.cooperation_enabled() or _allies().is_empty(): return false
	var identity: Dictionary = context.coordination_offer_identity()
	if identity.is_empty(): return false
	var point: Vector3 = candidate.destination.get("position", Vector3.INF)
	var side: float = (point - source.position).dot(source.front_axis)
	if (role == &"flank" and side >= -0.5) or (role == &"front_support" and side <= 0.5): return false
	if role == &"flank":
		if candidate.destination.get("flank_anchor", Vector3.INF).distance_to(source.position) > 0.001 or candidate.destination.get("flank_axis", Vector3.ZERO).distance_to(source.front_axis) > 0.001: return false
	var lifetime: float = float(source.valid_until) - context.coordination_now()
	if lifetime <= 0.0: return false
	var tactical_key := "flank:%s" % source.evidence_id
	var position_key := "%s:%s:%s" % [tactical_key, role, point]
	var offer_key := "%s:%s:%s" % [actor.get_instance_id(), position_key, identity.navigation_revision]
	candidate.coordination_offer_key = offer_key
	candidate.coordination_role = role
	candidate.coordination_staging_position = point if role in [&"front_support", &"team_position"] else actor.global_position
	candidate.known_position = source.position
	var actual := _own_actual_support() if role == &"front_support" else {"ready": false, "seconds": 0.0}
	var seconds: float = float(candidate.destination.get("route_seconds", 0.0))
	var offer: Dictionary = identity.duplicate()
	offer.merge({"scope": &"tactical", "owner_action": action_id, "offer_key": offer_key, "role": role,
		"position_set_key": position_key, "position": point, "target_id": source.target_id, "evidence_id": source.evidence_id,
		"path_summary": {"tactical_key": tactical_key, "tactical_anchor": source.position, "tactical_axis": source.front_axis,
			"side": -1 if role == &"flank" else 1, "holds_front": role == &"front_support",
			"posture": candidate.destination.get("team_posture", &"disperse" if role == &"flank" else &"hold"),
			"expected_fire_seconds": float(candidate.cooperation.get("support_seconds", 0.0)) if actor.can_use_firearms() else 0.0,
			"staging_position": candidate.coordination_staging_position, "staging_seconds": seconds if role in [&"front_support", &"team_position"] else 0.0},
		"travel_seconds": seconds, "unavailable_seconds": candidate.outcome.unavailable_seconds,
		"exposed_seconds": candidate.outcome.exposed_seconds, "information_loss": candidate.outcome.information_loss,
		"movement_possible": actor.can_move() and not actor.is_vaulting() and not actor.melee_active,
		"fire_ready": actual.ready, "measured_support_seconds": actual.seconds if actual.ready else 0.0,
		"captured_at": context.evidence_elapsed_seconds, "valid_until": context.evidence_elapsed_seconds + minf(0.75, lifetime)})
	_coordination_offers.append(offer)
	_coordination_local_candidates[offer_key] = candidate.duplicate(true)
	while _coordination_local_candidates.size() > 12: _coordination_local_candidates.erase(_coordination_local_candidates.keys()[0])
	return true

func _validate_coordinated(candidate: Dictionary, visible: bool) -> bool:
	if not _unified_coordinator() or not is_enabled() or not context.cooperation_enabled() or actor.is_vaulting() or actor.melee_active: return false
	var assignment: Dictionary = context.coordination_assignment()
	if assignment.is_empty() or assignment.get("owner_action") != action_id or assignment.get("role") != candidate.get("coordination_role") or not assignment.get("allowed_offer_keys", []).has(candidate.get("coordination_offer_key", "")): return false
	if assignment.get("role") == &"front_support":
		if not actor.can_use_firearms() or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading: return false
		if actor.global_position.distance_to(candidate.destination.position) <= 0.35:
			return visible and _hold_support_prediction(minf(context.utility_horizon_seconds, float(assignment.expires_at) - context.coordination_now())).support_seconds > 0.0
		return _position_route_valid(candidate)
	if assignment.get("role") == &"team_position": return _position_route_valid(candidate)
	if not actor.can_move(): return false
	if not _coordination_assignment.is_empty(): return _coordinated_valid(visible)
	var route: Dictionary = FlankRoute.assess(context, candidate.destination)
	return not route.is_empty() and route.position.distance_to(candidate.destination.position) <= 0.001 and float(route.route_seconds) < float(assignment.expires_at) - context.coordination_now()

func _position_route_valid(candidate: Dictionary) -> bool:
	if not actor.can_move() or not candidate.get("destination", {}).has("checkpoints"): return false
	var point: Vector3 = candidate.destination.position
	if not context.is_position_free(point): return false
	var path: PackedVector3Array = selection._path_to(actor.global_position, point)
	if path.is_empty(): return false
	if actor.can_use_firearms():
		var target: Vector3 = context.known_target_point(candidate.known_position)
		var origin: Vector3 = actor.get_posture_muzzle_position(false, point)
		return target.is_finite() and origin.distance_to(target) <= actor.weapon.fire_range and context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target))
	return true

func _validate_recommended(candidate: Dictionary) -> bool:
	if not is_enabled() or context.cooperation_level() != 1 or not actor.can_move() or actor.is_vaulting() or actor.melee_active: return false
	var advice: Dictionary = candidate.get("coordination_recommendation", {})
	if not context.cooperation.recommendation_available(context, advice, candidate.get("coordination_offer_key", "")): return false
	if not _recommendation.is_empty(): return _recommended_valid()
	var route: Dictionary = FlankRoute.assess(context, candidate.destination)
	return not route.is_empty() and float(route.route_seconds) < float(advice.expires_at) - context.coordination_now()

func _begin_recommended(candidate: Dictionary, visible: bool) -> bool:
	if not _validate_recommended(candidate): return false
	reset()
	_recommendation = candidate.coordination_recommendation.duplicate(true)
	destination = candidate.destination.position
	_known = candidate.known_position
	_target_id = candidate.target_id
	_remaining = maxf(0.0, float(_recommendation.expires_at) - context.coordination_now())
	_checkpoints = candidate.destination.get("checkpoints", PackedVector3Array())
	_segment = int(candidate.get("segment_index", 0))
	_segment_committed = true
	_route_position = actor.global_position
	phase = Phase.MOVE
	actor.agent.target_position = _move_target()
	return super.begin(candidate, visible)

func _recommended_valid() -> bool:
	if not _running or not is_enabled() or context.cooperation_level() != 1 or _remaining <= 0.0: return false
	var advice: Dictionary = context.coordination_recommendation()
	if advice.is_empty() or advice.recommendation_id != _recommendation.get("recommendation_id") or not advice.accepted: return false
	if actor.can_use_firearms() and actor.ammo.magazine_rounds <= 0 and not actor.ammo.is_reloading: return false
	return _target_id == context.cooperation_target_id() and not _checkpoints.is_empty()

func _begin_coordinated(candidate: Dictionary, visible: bool) -> bool:
	if not _validate_coordinated(candidate, visible): return false
	var assignment: Dictionary = candidate.get("coordination_assignment", {})
	if assignment.is_empty(): return false
	reset()
	_coordination_assignment = assignment.duplicate(true)
	_coordination_complete = false
	_coordination_route_valid = true
	destination = candidate.destination.position
	_known = candidate.known_position
	_target_id = candidate.target_id
	_remaining = maxf(0.0, float(assignment.expires_at) - context.coordination_now())
	_waiting = maxf(0.1, float(_setting(&"wait_seconds", 1.2)))
	_hold_remaining = _remaining
	_checkpoints = candidate.destination.get("checkpoints", PackedVector3Array())
	_segment = 0
	_segment_committed = assignment.role != &"flank"
	phase = Phase.WAIT_SUPPORT if assignment.role == &"flank" else (Phase.HOLD if _checkpoints.is_empty() else Phase.MOVE)
	if assignment.role == &"front_support":
		_front_contact_until = context.coordination_now() + maxf(0.0, float(_setting(&"support_recovery_seconds", 2.0)))
	_route_position = actor.global_position
	actor.agent.target_position = actor.global_position
	# No old flank claim: the caller commits its prepared assignment after begin.
	return super.begin(candidate, visible)

func _coordinated_valid(visible: bool) -> bool:
	if not _running or _coordination_assignment.is_empty() or not is_enabled() or not context.cooperation_enabled(): return false
	var assignment: Dictionary = context.coordination_assignment()
	if assignment.is_empty() or not assignment.get("accepted", false) or float(assignment.expires_at) <= context.coordination_now(): return false
	for key in [&"generation", &"team_id", &"plan_id", &"assignment_id", &"assignment_revision"]:
		if assignment.get(key) != _coordination_assignment.get(key): return false
	if assignment.role == &"front_support":
		# A passing ally may briefly occlude the held firing position. Preserve its
		# bounded commitment, while Fire and published support remain unavailable.
		if not actor.can_use_firearms() or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading: return false
		if not _checkpoints.is_empty() and actor.global_position.distance_to(destination) > 0.35:
			return actor.can_move() and _coordination_route_valid
		return visible or context.coordination_now() < _front_contact_until
	return _coordination_route_valid and not _checkpoints.is_empty()

func _coordinated_candidate() -> Dictionary:
	var candidate := plan.duplicate(true)
	var horizon: float = context.utility_horizon_seconds
	if phase == Phase.HOLD:
		var prediction := _hold_support_prediction(minf(_remaining, horizon))
		candidate.outcome.unavailable_seconds = minf(horizon, prediction.estimated_start_seconds)
		candidate.outcome.exposed_seconds = context._reload_exposure(actor.global_position, _known) * horizon
		candidate.outcome.information_loss = 0.0 if context.sees_player else horizon
		candidate.cooperation.support_seconds = prediction.support_seconds
		candidate.cooperation.estimated_start_seconds = prediction.estimated_start_seconds
	else:
		candidate.segment_index = _segment
		candidate.destination.path = selection._path_to(actor.global_position, _move_target())
		var assessment: Dictionary = {}
		if candidate.get("coordination_role") == &"flank": assessment = _assess_flank(candidate.destination, true)
		else:
			var point: Dictionary = candidate.destination.duplicate()
			point.erase("checkpoints")
			assessment = evaluate_point(point)
		if not assessment.is_empty():
			candidate.outcome = _candidate(assessment).outcome
	return candidate

func execution_contract(visible: bool) -> Dictionary:
	if _coordination_assignment.is_empty():
		return {"valid": valid(visible), "segment_boundary": not _segment_committed or phase == Phase.HOLD,
			"remaining_seconds": maxf(0.0, _remaining), "progress": 0.0, "ready_for_phase": false}
	var assignment: Dictionary = context.coordination_assignment()
	var executable := _coordinated_valid(visible)
	var staged: bool = executable and not actor.is_vaulting() and not actor.melee_active and actor.global_position.distance_to(plan.get("coordination_staging_position", Vector3.INF)) <= 0.35
	if assignment.get("role") == &"front_support": staged = staged and _own_actual_support().ready
	elif assignment.get("role") == &"flank": staged = staged and actor.can_move() and phase == Phase.WAIT_SUPPORT and _coordination_route_valid
	else: staged = staged and _coordination_route_valid and phase == Phase.HOLD
	return {"valid": executable, "segment_boundary": not _segment_committed or phase == Phase.HOLD,
		"remaining_seconds": maxf(0.0, float(assignment.get("expires_at", 0.0)) - context.coordination_now()),
		"progress": 1.0 if _coordination_complete else float(_segment) / maxf(1.0, float(_checkpoints.size())),
		"ready_for_phase": staged, "complete": executable and _coordination_complete}

func _tick_coordinated(delta: float, visible: bool) -> Dictionary:
	plan.erase("support_request")
	var assignment: Dictionary = context.coordination_assignment()
	_remaining = maxf(0.0, float(assignment.get("expires_at", 0.0)) - context.coordination_now())
	if not _coordinated_valid(visible):
		_finish(false)
		return motion(Vector3.ZERO)
	if (assignment.role == &"front_support" and actor.global_position.distance_to(destination) <= 0.35) or _coordination_complete:
		phase = Phase.HOLD
		if assignment.role == &"front_support" and visible:
			_front_contact_until = context.coordination_now() + maxf(0.0, float(_setting(&"support_recovery_seconds", 2.0)))
		context.state = context.State.HOLD_POSITION
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible))
	_support_grace = float(_setting(&"support_recovery_seconds", 2.0)) if _support_ready() else maxf(0.0, _support_grace - delta)
	var target := _move_target()
	_recheck -= maxf(0.0, delta)
	if _recheck <= 0.0:
		_recheck = 0.25
		var path: PackedVector3Array = selection._path_to(actor.global_position, target)
		_coordination_route_valid = context.is_position_free(target) and (FlankRoute.safe_path(path, _known) if assignment.role == &"flank" else not path.is_empty())
		if not _coordination_route_valid:
			_finish(true)
			return motion(Vector3.ZERO)
		_route_distance = selection._path_length_from_path(path)
		_direct_final = _route_distance <= actor.global_position.distance_to(target) + 0.08
	if phase == Phase.WAIT_SUPPORT:
		if assignment.phase != &"executing" or float(assignment.release_at) < 0.0 or context.coordination_now() < float(assignment.release_at):
			return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible))
		if not _support_ready():
			_waiting -= maxf(0.0, delta)
			if _waiting <= 0.0: _finish(false)
			return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible) if _running else {})
		phase = Phase.MOVE
		_segment_committed = true
		_had_support = true
	if not _segment_committed:
		_checkpoint_wait = maxf(0.0, _checkpoint_wait - delta)
		if assignment.role == &"flank" and not _support_continues():
			if _checkpoint_wait <= 0.0: _finish(false)
			return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible) if _running else {})
		_segment_committed = true
	var distance: float = context._horizontal_distance(target)
	if assignment.role == &"flank" and _had_support and not _support_continues() and distance > 1.5:
		_finish(false)
		return motion(Vector3.ZERO)
	if distance <= 0.15:
		if _segment + 1 < _checkpoints.size():
			_segment += 1
			_segment_committed = false
			_checkpoint_wait = float(_setting(&"support_recovery_seconds", 2.0))
			_recheck = 0.0
			_stuck = 0.0
			_waypoint = Vector3.INF
			actor.agent.target_position = actor.global_position
			context.invalidate_utility()
		else:
			_coordination_complete = assignment.role != &"front_support"
			phase = Phase.HOLD
			actor.agent.target_position = actor.global_position
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible))
	actor.agent.target_position = target
	var next: Vector3 = actor.agent.get_next_path_position()
	if distance <= 0.7 and _direct_final: next = target
	if actor.agent.is_navigation_finished() and distance > 0.7:
		_finish(true)
		return motion(Vector3.ZERO)
	var waypoint_distance: float = context._horizontal_distance(next)
	if not _waypoint.is_finite() or _waypoint.distance_to(next) > 0.25:
		_waypoint = next
		_best_distance = INF
	if waypoint_distance < _best_distance - 0.04:
		_best_distance = waypoint_distance
		_stuck = 0.0
	else: _stuck += maxf(0.0, delta)
	if _stuck >= 1.5:
		_finish(true)
		return motion(Vector3.ZERO)
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	context.state = context.State.REPOSITION
	if assignment.role != &"front_support" and not direction.is_zero_approx() and actor.can_move(): plan.support_request = {"kind": &"advance", "duration": minf(context.utility_horizon_seconds, _remaining), "lane_id": &"target"}
	return motion(direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * delta)), 1.0, _known - actor.global_position, _fire(visible))
