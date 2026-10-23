extends "res://scripts/enemy/actions/enemy_cover_action.gd"

func command_roles() -> Array[StringName]:
	return [&"shelter"]

func command_default_assignment() -> bool:
	return false

func command_site_offer(query: Dictionary, site: Dictionary) -> Dictionary:
	if not query.body.visible or not context.fire.fire_while_moving or query.body.rounds <= 0 or query.body.reloading: return {}
	var offer := super.command_site_offer(query, site)
	if offer.is_empty() or offer.get("retry_detour", false): return offer
	var speed: float = _setting(&"covering_retreat_speed_multiplier", 0.8)
	var seconds: float = selection._path_length_from_path(offer.route) / maxf(0.1, query.body.move_speed * speed)
	offer.speed_multiplier = speed
	offer.travel_seconds = seconds
	# Moving fire offsets unavailable fire time, not the real travel duration.
	offer.estimate = maxf(0.0, float(offer.estimate) - float(offer.tactical.travel)) + seconds * 0.25
	offer.tactical.travel = seconds
	offer.tactical.sustainable_fire = true
	offer.moving_fire = true
	return offer

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
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
		result.append(candidate)
	return result
