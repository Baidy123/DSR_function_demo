extends "res://scripts/enemy/actions/enemy_cover_action.gd"

func assignment_escape(candidate: Dictionary, visible: bool) -> bool:
	if candidate.get("mode") != &"covering_retreat" or not visible or not context.fire.fire_while_moving or not actor.can_use_firearms(): return false
	if actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading: return false
	return _defensive_cover_escape(candidate, visible)

func collect_candidates(visible: bool) -> Array[Dictionary]:
	_team_offers.clear()
	var result: Array[Dictionary] = []
	if _running and plan.has("coordination_role") and _team_assignment_valid(plan): return [plan.duplicate(true)]
	if not visible or not context.fire.fire_while_moving or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading:
		return result
	var horizon: float = context.utility_horizon_seconds
	var threat: Vector3 = context._known_reload_threat()
	for destination in transfer_candidates():
		if not _valid_cover(destination): continue
		destination.path = selection._path_to(actor.global_position, destination.hide)
		var route: Dictionary = context.spatial.assess_cover_route(destination.path, threat, transfer.covering_retreat_speed_multiplier, 0.0, true)
		var exposed: float = route.exposure + context._reload_exposure(destination.hide, threat) * maxf(0.0, horizon - route.seconds)
		var candidate := option(destination, horizon - route.fire_seconds, exposed, horizon - minf(horizon, route.seconds))
		candidate.mode = &"covering_retreat"
		candidate.conceals = true
		candidate.support_request = {"kind": &"retreat", "duration": minf(horizon, route.seconds), "lane_id": &"target"}
		if _team_orders_enabled() and not assignment_escape(candidate, visible):
			# A planned strong retreat is issued with its cover, before movement.
			# Real self-preservation above remains immediately executable.
			if context._reload_risk_aversion() > 0.01 and _offer_team_candidate(candidate, &"assisted_retreat", {"action_seconds": route.seconds, "travel_seconds": route.seconds, "defensive_need": true}): result.append(candidate)
		else: result.append(candidate)
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	return (not candidate.has("coordination_role") or _team_assignment_valid(candidate)) and super.validate(candidate, visible)

func tick(delta: float, visible: bool) -> Dictionary:
	if plan.has("coordination_role") and not plan.get("team_released", false):
		var support: Dictionary = context.coordination_support_state()
		if not (support.get("released", false) and support.get("ready", false)) and not assignment_escape(plan, visible): return _team_wait_fire(visible)
		plan.team_released = true
	return super.tick(delta, visible)

func execution_contract(visible: bool) -> Dictionary:
	if not plan.has("coordination_role"): return super.execution_contract(visible)
	var assignment: Dictionary = context.coordination_assignment()
	return {"valid": valid(visible) and _team_assignment_valid(plan), "segment_boundary": transfer.phase == transfer.Phase.HIDE,
		"ready_for_phase": not plan.get("team_released", false), "remaining_seconds": maxf(0.0, float(assignment.get("expires_at", 0.0)) - context.coordination_now()),
		"complete": transfer.phase == transfer.Phase.HIDE, "progress": 1.0 if transfer.phase == transfer.Phase.HIDE else 0.0}
