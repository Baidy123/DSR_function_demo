extends "res://scripts/enemy/actions/enemy_action.gd"

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

func _evidence() -> Dictionary:
	return context.cooperation_target_evidence()

func _live_evidence(evidence: Dictionary) -> bool:
	return not evidence.is_empty() and evidence.get("position", Vector3.INF).is_finite() and context.evidence_elapsed_seconds < float(evidence.get("valid_until", -INF))

func _allies() -> Array:
	var snapshot: Dictionary = context.cooperation_snapshot()
	return snapshot.get("members", []).filter(func(member): return member.get("id", 0) != actor.get_instance_id() and member.get("can_cooperate", false) and member.get("target_id", 0) == context.cooperation_target_id())

func _support_ready(segment_seconds: float = -1.0) -> bool:
	# The public member snapshot is populated from actual fire execution, not claims.
	if segment_seconds < 0.0:
		segment_seconds = context._horizontal_distance(destination) / maxf(0.1, actor.move_speed) if destination.is_finite() else 0.5
	var required := minf(0.5, maxf(0.1, segment_seconds))
	for member: Dictionary in _allies():
		if member.get("ready", false) and not member.get("moving", false) and float(member.get("support_seconds", 0.0)) >= required: return true
	return false

func _fresh_allowed() -> bool:
	if _failed_generation != context.memory_generation:
		_failed_generation = context.memory_generation
		_failed_until = 0.0
	return context.evidence_elapsed_seconds >= _failed_until

func evaluation_points() -> Array:
	if not is_enabled() or not context.cooperation_enabled() or actor.move_speed <= 0.0 or _allies().is_empty(): return []
	var evidence := _evidence()
	if not _live_evidence(evidence): return []
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
	return points

func evaluation_weight() -> int:
	return 2

func evaluation_priority_count() -> int:
	return 2

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
	var known: Vector3 = evidence.position
	var position: Vector3 = point.get("position", Vector3.INF)
	if not position.is_finite() or actor.global_position.distance_to(position) < 0.5 or not context.is_position_free(position): return {}
	if context.is_utility_destination_blocked(position): return {}
	var path: PackedVector3Array = selection._path_to(actor.global_position, position)
	if path.is_empty(): return {}
	var quality := _angle_gain(position, known)
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
	var wait: float = 0.0 if _support_ready(route.seconds) else maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
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
	return result

func _candidate(assessment: Dictionary) -> Dictionary:
	var candidate := option(assessment.destination, assessment.unavailable, assessment.exposed, assessment.information, &"advance")
	candidate.cooperation = assessment.cooperation.duplicate(true)
	candidate.target_id = context.cooperation_target_id()
	candidate.known_position = _evidence().get("position", Vector3.INF)
	return candidate

func _slot_available(task: Dictionary) -> bool:
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
	var result: Array[Dictionary] = []
	if not is_enabled() or not context.cooperation_enabled() or actor.move_speed <= 0.0: return result
	if actor.can_use_firearms() and actor.ammo.magazine_rounds <= 0 and not actor.ammo.is_reloading: return result
	if _running:
		if valid(context.sees_player):
			var continuing := plan.duplicate(true)
			var moving_seconds: float = maxf(_route_distance, context._horizontal_distance(destination)) / maxf(0.1, actor.move_speed) if phase != Phase.HOLD else 0.0
			var wait: float = _waiting if phase == Phase.WAIT_SUPPORT else 0.0
			continuing.cooperation.movement_start_seconds = wait
			continuing.cooperation.movement_seconds = minf(moving_seconds, maxf(0.0, _remaining - wait))
			continuing.cooperation.estimated_start_seconds = wait + moving_seconds
			continuing.cooperation.support_seconds = minf(float(continuing.cooperation.get("support_seconds", 0.0)), _remaining)
			if actor.can_use_firearms():
				continuing.outcome.unavailable_seconds = maxf(float(continuing.outcome.unavailable_seconds), context.spatial._ammo_wait(context))
				continuing.cooperation.support_seconds = minf(float(continuing.cooperation.support_seconds), maxf(0.0, context.utility_horizon_seconds - context.spatial._ammo_wait(context)))
			result.append(continuing)
		return result
	if not _fresh_allowed() or not _live_evidence(_evidence()) or _allies().is_empty(): return result
	for assessment: Dictionary in context.spatial.assessments(self):
		if not assessment.is_empty() and _slot_available(assessment.cooperation): result.append(_candidate(assessment))
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	if not candidate.get("route", {}).is_empty(): return false
	if not is_enabled() or not context.cooperation_enabled() or candidate.get("target_id", 0) != context.cooperation_target_id(): return false
	if not _live_evidence(_evidence()) or not super.validate(candidate, visible): return false
	if not _slot_available(candidate.get("cooperation", {})): return false
	if _running and candidate.get("destination", {}).get("position", Vector3.INF).is_equal_approx(destination): return true
	return not evaluate_point(candidate.destination).is_empty()

func begin(candidate: Dictionary, visible: bool) -> bool:
	if not validate(candidate, visible): return false
	var task: Dictionary = candidate.cooperation.duplicate(true)
	task.owner_action = action_id
	task.duration = maxf(0.1, float(_setting(&"plan_seconds", 4.0))) + maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
	var claimed: Dictionary = context.cooperation_claim(task)
	if claimed.is_empty(): return false
	reset()
	_claim = claimed
	super.begin(candidate, visible)
	destination = candidate.destination.position
	_route_distance = selection._path_length_from_path(candidate.destination.path)
	_route_position = actor.global_position
	_known = candidate.known_position
	_target_id = candidate.target_id
	_remaining = task.duration
	_waiting = maxf(0.0, float(_setting(&"wait_seconds", 1.2)))
	_had_support = _support_ready()
	phase = Phase.MOVE if _had_support else Phase.WAIT_SUPPORT
	actor.agent.target_position = destination if phase == Phase.MOVE else actor.global_position
	return true

func valid(_visible: bool) -> bool:
	if not _running or phase == Phase.NONE or not is_enabled() or not context.cooperation_enabled(): return false
	if actor.can_use_firearms() and actor.ammo.magazine_rounds <= 0 and not actor.ammo.is_reloading: return false
	var evidence := _evidence()
	return _remaining > 0.0 and _target_id == context.cooperation_target_id() and _live_evidence(evidence) and evidence.position.distance_to(_known) <= 2.0

func _fire(visible: bool) -> Dictionary:
	return {"owner": action_id, "mode": &"visible"} if visible and actor.can_use_firearms() else {}

func tick(delta: float, visible: bool) -> Dictionary:
	_remaining = maxf(0.0, _remaining - maxf(0.0, delta))
	if not valid(visible) or not context.cooperation_update(_claim, {"remaining": _remaining, "position": actor.global_position}):
		_finish(false)
		return motion(Vector3.ZERO)
	if phase == Phase.WAIT_SUPPORT:
		_waiting = maxf(0.0, _waiting - delta)
		if _support_ready():
			_had_support = true
			phase = Phase.MOVE
			actor.agent.target_position = destination
		elif _waiting <= 0.0:
			_finish(true)
		context.state = context.State.HOLD_POSITION
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible) if _running else {})
	if phase == Phase.HOLD:
		_hold_remaining = maxf(0.0, _hold_remaining - delta)
		if _hold_remaining <= 0.0 or not visible: _finish(false)
		context.state = context.State.HOLD_POSITION
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible) if _running else {})
	var distance: float = context._horizontal_distance(destination)
	if _route_position.is_finite():
		var travelled: Vector3 = actor.global_position - _route_position
		_route_distance = maxf(0.0, _route_distance - Vector2(travelled.x, travelled.z).length())
	_route_position = actor.global_position
	# Losing support far from the destination returns the current position to Utility.
	# A nearly completed segment can still reach its previously checked safe point.
	if _had_support and not _support_ready() and distance > 1.5:
		_finish(false)
		return motion(Vector3.ZERO)
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.25
		var path: PackedVector3Array = selection._path_to(actor.global_position, destination)
		if not context.is_position_free(destination) or path.is_empty():
			_finish(true)
			return motion(Vector3.ZERO)
		_route_distance = selection._path_length_from_path(path)
	if distance <= 0.15:
		if not visible or not actor.can_use_firearms():
			_finish(false)
			return motion(Vector3.ZERO)
		phase = Phase.HOLD
		_hold_remaining = maxf(0.1, float(_setting(&"lane_hold_seconds", 1.2)))
		actor.agent.target_position = actor.global_position
		return motion(Vector3.ZERO, 1.0, _known - actor.global_position, _fire(visible))
	actor.agent.target_position = destination
	var next: Vector3 = actor.agent.get_next_path_position()
	if actor.agent.is_navigation_finished() and distance > 0.15:
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

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running: _finish(false)

func state_label() -> String:
	return ["", "等待友军掩护", "协同侧向推进", "保持交叉火力"][phase]
