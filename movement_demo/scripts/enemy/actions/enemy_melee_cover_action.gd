extends "res://scripts/enemy/actions/enemy_cover_action.gd"

const Approach = preload("res://scripts/enemy/services/enemy_melee_approach.gd")

func evaluation_channel() -> StringName:
	return &"melee_cover_geometry"

func evaluate_point(point: Variant) -> Dictionary:
	var candidate := _advance_candidate(point, false)
	if candidate.is_empty(): return {}
	var outcome: Dictionary = candidate.outcome
	return {"destination": candidate.destination, "cost": context.spatial.score(outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss)}

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not _has_recent_target() or context.melee.can_request(visible): return candidates
	for destination in transfer_candidates():
		var continuing: bool = _running and transfer.phase == transfer.Phase.RUN_TO_COVER and destination.body == transfer.active_cover_body and destination.hide.is_equal_approx(transfer.hide_position)
		var candidate := _advance_candidate(destination, continuing)
		if not candidate.is_empty(): candidates.append(candidate)
	return candidates

func _has_recent_target() -> bool:
	return is_enabled() and context.has_visual_memory and context.is_alerted and not context.noise_search_origin.is_finite() and context.utility_unseen_seconds <= maxf(0.0, float(_setting(&"cover_memory_seconds", 5.0)))

func _advance_candidate(destination: Dictionary, continuing: bool) -> Dictionary:
	if not _has_recent_target() or actor.move_speed <= 0.0 or not _valid_cover(destination): return {}
	var target: Vector3 = context.last_known_position
	var progress: float = context._horizontal_distance(target) - context._horizontal_distance_between(destination.hide, target)
	if not continuing and progress < maxf(0.1, float(_setting(&"cover_minimum_progress", 0.6))): return {}
	var path: PackedVector3Array = selection._path_to(actor.global_position, destination.hide)
	var route: Dictionary = context.spatial.assess_cover_route(path, target, transfer.run_speed_multiplier, 0.0)
	var horizon: float = context.utility_horizon_seconds
	var exposed: float = route.exposure + context._reload_exposure(destination.hide, target) * maxf(0.0, horizon - route.seconds)
	var candidate := option(destination, horizon, Approach.opportunity_exposure(context, exposed), horizon if not context.sees_player else maxf(0.0, horizon - route.seconds), &"advance")
	candidate.conceals = true
	return candidate

func validate(candidate: Dictionary, visible: bool) -> bool:
	return _has_recent_target() and not _advance_candidate(candidate.destination, false).is_empty() and super.validate(candidate, visible)

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	context.state = context.State.APPROACH
	return true

func valid(visible: bool) -> bool:
	return _has_recent_target() and is_instance_valid(transfer.active_cover_body) and super.valid(visible)

func tick(delta: float, visible: bool) -> Dictionary:
	var output := super.tick(delta, visible)
	# 掩体是推进途中的落点；到位后交回共同决策，不能长期停在同一掩体。
	if transfer.phase == transfer.Phase.HIDE:
		_running = false
		output.running = false
	return output

func can_interrupt(next: Dictionary, visible: bool) -> bool:
	return context.observed_reload_window() > 0.0 or context.melee.can_request(visible) or super.can_interrupt(next, visible)

func hold_released() -> bool:
	return context.observed_reload_window() > 0.0 or context.melee.can_request(context.sees_player)

func state_label() -> String:
	return "绕行接近掩体" if transfer.cover_detour_active else "掩体接近"
