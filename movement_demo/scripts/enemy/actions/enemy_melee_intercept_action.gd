extends "res://scripts/enemy/actions/enemy_action.gd"

const Prediction = preload("res://scripts/enemy/services/enemy_melee_interception.gd")
const Approach = preload("res://scripts/enemy/services/enemy_melee_approach.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
var _retry_at := 0.0
var _generation := -1

func _parameters() -> Dictionary:
	return {"horizon": float(_setting(&"intercept_horizon_seconds", 1.8)),
		"distance": float(_setting(&"intercept_max_distance", 6.0)),
		"memory": float(_setting(&"intercept_memory_seconds", 0.6)),
		"speed": float(_setting(&"intercept_speed_multiplier", 2.0)),
		"gain": float(_setting(&"intercept_min_gain_seconds", 0.25))}

func _available() -> bool:
	return is_enabled() and actor.can_move() and not actor.melee_active and actor.weapon != null and actor.weapon.melee_enabled and (_generation != context.memory_generation or context.evidence_elapsed_seconds >= _retry_at)

func _continuing(prediction: Dictionary) -> Dictionary:
	if not Prediction.valid(context, prediction, float(_setting(&"intercept_memory_seconds", 0.6))): return {}
	if not context.is_position_free(prediction.position): return {}
	var path: PackedVector3Array = Traffic.remaining(actor.global_position, prediction.path)
	if path.is_empty() or context.is_ally_path_blocked(actor.global_position, path): return {}
	var result := prediction.duplicate(true)
	result.path = path
	return result

func collect_candidates(_visible: bool) -> Array[Dictionary]:
	if not _available(): return []
	var predictions: Array[Dictionary] = []
	var continuing := _continuing(plan.get("interception", {})) if _running else {}
	if not continuing.is_empty(): predictions.append(continuing)
	else:
		for fraction in [0.6, 1.0]:
			var prediction := Prediction.propose(context, _parameters(), fraction)
			if not prediction.is_empty(): predictions.append(prediction)
	var candidates: Array[Dictionary] = []
	for prediction in predictions:
		var candidate := option({"position": prediction.position, "path": prediction.path}, 0.0, 0.0, 0.0, &"intercept")
		candidate.interception = prediction
		candidate.route_target = prediction.position
		candidate.outcome = Approach.contact_outcome(context, prediction.path, route_multiplier())
		candidate.outcome.unavailable_seconds = maxf(float(candidate.outcome.unavailable_seconds), float(prediction.crossing_at) - context.evidence_elapsed_seconds)
		candidate.outcome.preference_credit = float(prediction.gain) * maxf(0.0, context.utility_fire_weight)
		candidates.append(candidate)
	return candidates

func validate(candidate: Dictionary, _visible: bool) -> bool:
	return is_enabled() and Prediction.valid(context, candidate.get("interception", {}), float(_setting(&"intercept_memory_seconds", 0.6))) and context.is_position_free(candidate.destination.position)

func expand_route_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	# The full timed approach already includes the shoulder. A generic shortcut
	# must not replace it after its arrival window has been evaluated.
	return candidates

func valid(visible: bool) -> bool:
	return _running and (context.melee.is_active_for(action_id) or validate(plan, visible))

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	context.state = context.State.APPROACH
	return true

func tick(delta: float, visible: bool) -> Dictionary:
	if context.melee.is_active_for(action_id) or context.melee.can_request(visible):
		return motion(Vector3.ZERO, 1.0, Vector3.INF, {}, {"owner": action_id})
	if not valid(visible):
		_reject()
		_running = false
		return motion(Vector3.ZERO)
	var path: PackedVector3Array = Traffic.remaining(actor.global_position, plan.interception.path)
	while path.size() > 1 and context._horizontal_distance(path[1]) < 0.06: path.remove_at(1)
	if path.size() <= 1: return motion(Vector3.ZERO)
	var next: Vector3 = path[1]
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	var output := motion(direction.normalized(), minf(route_multiplier(), direction.length() / maxf(0.001, actor.move_speed * delta)))
	output.stop_position = next
	return output

func can_interrupt(_next: Dictionary, _visible: bool) -> bool:
	return not context.melee.is_active_for(action_id)

func route_multiplier() -> float:
	return float(_setting(&"intercept_speed_multiplier", 2.0))

func command_roles() -> Array[StringName]:
	return [&"engage", &"flank"] if actor.weapon != null and actor.weapon.melee_enabled else []

func command_default_assignment() -> bool:
	return false

func prepare_command_offers(query: Dictionary, cursor: Dictionary, deadline_usec: int) -> Dictionary:
	if not _available() or Time.get_ticks_usec() >= deadline_usec: return {"offers": [], "next_cursor": cursor, "done": not _available()}
	var index: int = cursor.get("index", 0)
	var prediction := _continuing(query.previous.get("interception", {}))
	if prediction.is_empty() and query.objective.get("phase") == &"contact" and index < 2:
		prediction = Prediction.propose(context, _parameters(), [0.6, 1.0][index])
	var offers: Array[Dictionary] = []
	if not prediction.is_empty():
		var site := {"position": prediction.position, "prepared_route": prediction.path, "approach_only": true,
			"role": &"engage", "look_position": query.objective.position,
			"site_key": "intercept:%s" % prediction.position}
		var offer := command_site_offer(query, site)
		if not offer.is_empty() and not offer.get("retry_detour", false):
			var seconds: float = selection._path_length_from_path(prediction.path) / maxf(0.1, actor.move_speed * route_multiplier())
			var exposure: float = offer.tactical.get("exposure", 0.0)
			# Catching a fleeing target earlier saves both unavailable contact
			# time and time spent exposed during pursuit, in the same cost units.
			var saved_pursuit: float = float(prediction.gain) * (1.0 + exposure)
			offer.estimate = maxf(0.0, float(offer.estimate) + maxf(seconds, float(prediction.crossing_at) - context.evidence_elapsed_seconds) - float(offer.travel_seconds) - saved_pursuit - exposure * (minf(3.0, offer.travel_seconds) - minf(3.0, seconds)))
			offer.travel_seconds = seconds
			offer.tactical.travel = seconds
			offer.speed_multiplier = route_multiplier()
			offer.contact_post = false
			offer.interception = prediction
			offer.allowed_phases = [&"contact", &"search"]
			offer.reconsider_at = context.coordination_now() + maxf(0.0, float(prediction.until) - context.evidence_elapsed_seconds)
			offer.plan_key = [action_id, prediction.position, prediction.captured_at]
			offer.stage = &"intercept"
			offers.append(offer)
	return {"offers": offers, "next_cursor": {"index": index + 1}, "done": index >= 1 or query.objective.get("phase") != &"contact"}

func validate_command_offer(query: Dictionary, offer: Dictionary) -> Dictionary:
	var result := super.validate_command_offer(query, offer)
	result.valid = result.valid and Prediction.valid(context, offer.get("interception", {}), float(_setting(&"intercept_memory_seconds", 0.6)))
	if not result.valid: result.reason = &"action_window"
	return result

func execute_command(delta: float, visible: bool) -> Dictionary:
	if not context.melee.is_active_for(action_id) and not context.melee.can_request(visible) and not Prediction.valid(context, command.get("interception", {}), float(_setting(&"intercept_memory_seconds", 0.6))):
		_reject()
		context.report_command(command, &"blocked", {"reason": &"action_window", "failure_scope": &"action"})
		return motion(Vector3.ZERO)
	return super.execute_command(delta, visible)

func _reject() -> void:
	_generation = context.memory_generation
	_retry_at = context.evidence_elapsed_seconds + 0.4
