extends "res://scripts/enemy/actions/enemy_action.gd"

var transfer = preload("res://scripts/enemy/actions/enemy_cover_motion.gd").new()

func setup(shared_context, section: StringName = &"") -> void:
	super.setup(shared_context, section)
	transfer.setup(context, action_id)

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not actor.can_use_firearms() or (actor.ammo.magazine_rounds > 0 and not actor.ammo.is_reloading and not _running):
		return result
	var horizon: float = context.utility_horizon_seconds
	var threat: Vector3 = context._known_reload_threat()
	var seconds: float = context.spatial._reload_seconds(context)
	result.append(option({}, seconds, context.spatial._exposure(context, actor.global_position, threat) * horizon, 0.0, &"here"))
	if context.can_use_action(&"cover") and threat.is_finite() and not context.noise_search_origin.is_finite():
		var destinations: Array = context.spatial.cover_destinations()
		if _running and not plan.get("destination", {}).is_empty(): destinations.append(plan.destination)
		for destination in destinations:
			if not context.spatial.cover_valid(destination) or context.is_utility_destination_blocked(destination.hide): continue
			if context.avoid_position.is_finite() and context._horizontal_distance_between(destination.hide, context.avoid_position) < 0.9: continue
			destination.path = selection._path_to(actor.global_position, destination.hide)
			var moving: Dictionary = context.spatial.assess_route(context, destination.path, threat, transfer.run_speed_multiplier, seconds if actor.ammo.is_reloading else 0.0)
			var exposed: float = moving.exposure + context._reload_exposure(destination.hide, threat) * maxf(0.0, horizon - moving.seconds)
			var information: float = horizon if not visible else maxf(0.0, horizon - moving.seconds)
			if not actor.ammo.is_reloading: result.append(option(destination, moving.seconds + seconds, exposed, information, &"after_cover"))
			var walking: Dictionary = context.spatial.assess_route(context, destination.path, threat, transfer.run_speed_multiplier, seconds)
			var walking_exposure: float = walking.exposure + context._reload_exposure(destination.hide, threat) * maxf(0.0, horizon - walking.seconds)
			result.append(option(destination, maxf(walking.seconds, seconds), walking_exposure, horizon if not visible else maxf(0.0, horizon - walking.seconds), &"on_way"))
	for candidate in result:
		candidate.urgent = true
		candidate.conceals = not candidate.destination.is_empty()
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	return actor.can_use_firearms() and super.validate(candidate, visible) and (candidate.destination.is_empty() or (context.can_use_action(&"cover") and context.spatial.cover_valid(candidate.destination)))

func begin(candidate: Dictionary, visible: bool) -> bool:
	candidate.conceals = not candidate.destination.is_empty()
	super.begin(candidate, visible)
	if candidate.destination.is_empty():
		agent.target_position = actor.global_position
	else:
		context.utility_suppression_pending = false
		transfer.start_reload_transfer(candidate.destination, context._known_reload_threat())
	if candidate.plan != &"after_cover": actor.request_reload()
	return true

func valid(_visible: bool) -> bool:
	return _running and actor.can_use_firearms() and (plan.destination.is_empty() or (context.can_use_action(&"cover") and transfer.is_active()))

func tick(delta: float, visible: bool) -> Dictionary:
	var arrived: bool = plan.destination.is_empty() or transfer.phase == transfer.Phase.HIDE
	if arrived and not actor.ammo.is_reloading and actor.ammo.magazine_rounds > 0:
		_running = false
		context.avoid_position = Vector3.INF
		return motion(Vector3.ZERO)
	var direction := Vector3.ZERO
	if not arrived:
		agent.target_position = transfer.cover_detour_position if transfer.cover_detour_active else plan.destination.hide
		direction = transfer.step(delta, visible)
		if not transfer.is_active():
			_running = false
			context.avoid_position = plan.destination.hide
			return motion(Vector3.ZERO)
	if arrived and actor.ammo.magazine_rounds == 0 and not actor.ammo.is_reloading: actor.request_reload()
	var facing: Vector3 = direction if not direction.is_zero_approx() else context.last_known_position - actor.global_position
	return motion(direction, transfer.movement_multiplier() if not plan.destination.is_empty() else 1.0, facing)

func reset() -> void:
	transfer.reset()

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running and not plan.destination.is_empty():
		transfer.on_damage_received()
		_running = transfer.is_active()
