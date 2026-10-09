extends "res://scripts/enemy/actions/enemy_action.gd"

var transfer = preload("res://scripts/enemy/actions/enemy_cover_motion.gd").new()
var _transfer_reconsider := false
var low_cycle = preload("res://scripts/enemy/actions/enemy_low_cover_cycle.gd").new()

func evaluation_channel() -> StringName:
	return &"shelter_geometry"

func setup(shared_context, section: StringName = &"") -> void:
	super.setup(shared_context, section)
	transfer.setup(context, action_id, definition.parameters if definition != null else {})

func configuration_changed() -> void:
	super.configuration_changed()
	transfer.parameters = definition.parameters

func evaluation_points() -> Array:
	var points: Array = context.spatial.cover_points()
	if context.combat_type != context.CombatType.RANGED or not actor.can_use_firearms(): return points
	# Nearby crouch/stand alternatives must enter the same bounded queue before
	# distant pure-hide points; no extra synchronous scan is introduced.
	var radius: float = maxf(0.1, float(_setting(&"low_cover_preference_distance", 4.0)))
	var near: Array = points.filter(func(point): return point.get("crouch", false) and context._horizontal_distance(point.hide) <= radius)
	var other: Array = points.filter(func(point): return not (point.get("crouch", false) and context._horizontal_distance(point.hide) <= radius))
	near.append_array(other)
	return near

func evaluate_point(point: Variant) -> Dictionary:
	var assessment: Dictionary = context.spatial.assess_cover_point(point)
	if assessment.is_empty() or context.combat_type != context.CombatType.RANGED: return assessment
	if not assessment.destination.get("crouch", false) or not assessment.destination.body.is_low_cover() or not actor.can_use_firearms() or actor.ammo.is_reloading or actor.ammo.magazine_rounds <= 0: return assessment
	var threat: Vector3 = context._known_reload_threat()
	var route: Dictionary = context.spatial.assess_cover_route(assessment.destination.path, threat, transfer.run_speed_multiplier, 0.0)
	var burst := _low_cover_option(assessment.destination, route, threat, context.sees_player)
	if not burst.is_empty():
		var outcome: Dictionary = burst.outcome
		var cost: float = preload("res://scripts/enemy/enemy_utility_score.gd").score_outcome(context, outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss, outcome.preference_credit).cost
		assessment.cost = minf(assessment.cost, cost)
	return assessment

func transfer_candidates() -> Array:
	var destinations: Array = context.spatial.destinations(self)
	if transfer.is_active() and is_instance_valid(transfer.active_cover_body):
		var current := {"hide": transfer.hide_position, "body": transfer.active_cover_body, "crouch": transfer.crouch_hide}
		if not destinations.any(func(other): return other.body == current.body and other.hide.is_equal_approx(current.hide)):
			destinations.append(current)
	return destinations

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var threat: Vector3 = context._known_reload_threat()
	if not threat.is_finite() or context.noise_search_origin.is_finite() or actor.move_speed <= 0.0:
		return options
	var defensive_melee: bool = context.combat_type == context.CombatType.MELEE
	if defensive_melee and context.melee.can_request(visible): return options
	var under_pressure: bool = context.recent_damage_pressure > 0.0 or context.nearby_shot_pressure > 0.0
	var horizon: float = context.utility_horizon_seconds
	var information: float = 0.0 if visible else horizon
	for destination in transfer_candidates():
		# 近战的基础躲藏用于缓解新压力；低血量本身不能使其永久躲藏。
		# 压力途中消退仍完成当前转移，到位后保留探出／搜索／接敌的共同选择。
		var continuing: bool = _running and transfer.phase == transfer.Phase.RUN_TO_COVER and destination.body == transfer.active_cover_body and destination.hide.is_equal_approx(transfer.hide_position)
		if defensive_melee and not under_pressure and not continuing: continue
		if not _valid_cover(destination):
			continue
		destination.path = context.routes.planning_path(actor.global_position, destination.hide)
		var route: Dictionary = context.spatial.assess_cover_route(destination.path, threat, transfer.run_speed_multiplier, context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0)
		var exposed: float = route.exposure + context._reload_exposure(destination.hide, threat, -1.0, destination.get("crouch", false)) * maxf(0.0, horizon - route.seconds)
		var candidate := option(destination, horizon, exposed, maxf(information, horizon - minf(horizon, route.seconds)))
		candidate.conceals = true
		options.append(candidate)
		if not defensive_melee:
			var burst := _low_cover_option(destination, route, threat, visible)
			if not burst.is_empty(): options.append(burst)
	_assess_peek(threat, information, visible, options)
	return options

func _low_cover_option(destination: Dictionary, route: Dictionary, threat: Vector3, visible: bool) -> Dictionary:
	if not destination.get("crouch", false) or not destination.body.is_low_cover() or not actor.can_use_firearms(): return {}
	if actor.ammo.is_reloading or actor.ammo.magazine_rounds <= 0: return {}
	if not visible and not low_cycle.active() and (not context.has_visual_memory or context.utility_unseen_seconds > transfer.watch_seconds): return {}
	var point: Vector3 = destination.hide
	if not context.is_position_free(point): return {}
	var samples: PackedVector3Array = context.known_target_points(threat) if visible else PackedVector3Array([actor.get_posture_eye_position(false, threat)])
	if not selection.low_cover_attack_target(point, samples).is_finite(): return {}
	var horizon: float = context.utility_horizon_seconds
	var hide: float = maxf(0.0, float(_setting(&"low_cover_hide_seconds", 0.6)))
	var transition: float = actor.posture_seconds * 3.0
	var ready: float = route.seconds + hide + transition + maxf(context.fire.fire_reaction_seconds, maxf(context.fire.fire_pause_remaining, context.fire.shot_wait_seconds()))
	var shooting: float = minf(maxf(0.0, horizon - ready), context.fire.burst_window_seconds())
	var remaining: float = maxf(0.0, horizon - route.seconds)
	var upright: float = minf(remaining, actor.posture_seconds * 2.0 + context.fire.fire_reaction_seconds + shooting)
	var exposure: float = route.exposure + context._reload_exposure(point, threat, -1.0, true) * maxf(0.0, remaining - upright) + context._reload_exposure(point, threat) * upright
	var candidate := option(destination, horizon - shooting, exposure, minf(horizon, route.seconds + hide + actor.posture_seconds))
	candidate.mode = &"low_cover_burst"
	candidate.conceals = true
	var distance: float = context._horizontal_distance(point)
	var range_limit: float = maxf(0.1, float(_setting(&"low_cover_preference_distance", 4.0)))
	# Nearby walls retain the full configured preference. Only the outer half
	# of the radius fades it, so a one-metre approach is not penalized twice.
	var factor := clampf((range_limit - distance) / (range_limit * 0.5), 0.0, 1.0)
	candidate.outcome.preference_credit = maxf(0.0, float(_setting(&"low_cover_preference", 8.0))) * factor
	return candidate

func _valid_cover(destination: Dictionary) -> bool:
	return not context.is_utility_destination_blocked(destination.hide) and (not context.avoid_position.is_finite() or context._horizontal_distance_between(destination.hide, context.avoid_position) >= 0.9) and context.spatial.cover_valid(destination)

func _assess_peek(threat: Vector3, information: float, visible: bool, options: Array[Dictionary]) -> void:
	if not transfer.is_active() or not is_instance_valid(transfer.active_cover_body):
		return
	var body = transfer.active_cover_body
	if visible and not body.is_low_cover(): return
	var points: Array[Vector3] = []
	for candidate in body.get_candidates(threat + Vector3.UP * 0.8, actor.global_position):
		if candidate.get("crouch", false) and candidate.hide.distance_to(transfer.hide_position) < 0.25 and not points.has(candidate.stand): points.append(candidate.stand)
		for point in candidate.peeks:
			if not points.has(point): points.append(point)
	for point in points:
		if context.is_utility_destination_blocked(point) or context.utility_rejected_attack_points.any(func(previous): return previous.distance_to(point) < 0.25):
			continue
		if not context.is_position_free(point) or not selection.has_clear_line(actor.get_posture_eye_position(false, point), actor.get_posture_eye_position(false, threat)):
			continue
		var path: PackedVector3Array = context.routes.planning_path(actor.global_position, point)
		if path.is_empty(): continue
		var route: Dictionary = context.spatial.assess_route(context, path, threat, transfer.peek_speed_multiplier, context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0)
		var horizon: float = context.utility_horizon_seconds
		var exposed: float = route.exposure + context._reload_exposure(point, threat) * maxf(0.0, horizon - route.seconds)
		var stand_peek: bool = body.is_low_cover() and point.distance_to(transfer.hide_position) < 0.05
		var unavailable: float = minf(horizon, route.seconds + actor.posture_seconds + context.spatial._ammo_wait(context)) if stand_peek and visible else horizon
		var candidate := option({"hide": transfer.hide_position, "position": point, "body": body, "path": path, "stand_peek": stand_peek}, unavailable, exposed, information * minf(1.0, route.seconds / horizon))
		candidate.mode = &"peek"
		candidate.conceals = true
		options.append(candidate)

func validate(candidate: Dictionary, visible: bool) -> bool:
	return super.validate(candidate, visible) and (candidate.get("mode") == &"peek" or _valid_cover(candidate.destination))

func begin(candidate: Dictionary, visible: bool) -> bool:
	_transfer_reconsider = false
	low_cycle.reset()
	candidate.conceals = true
	super.begin(candidate, visible)
	context.utility_suppression_pending = false
	if candidate.get("mode") == &"peek":
		transfer.start_utility_peek(candidate.destination, context._known_reload_threat())
	else:
		transfer.start_reload_transfer(candidate.destination, context._known_reload_threat(), candidate.get("mode") == &"covering_retreat")
	if candidate.get("mode") == &"low_cover_burst": low_cycle.begin(context, float(_setting(&"low_cover_hide_seconds", 0.6)))
	return true

func valid(_visible: bool) -> bool:
	return _running and is_enabled() and transfer.is_active() and (not low_cycle.active() or actor.can_use_firearms())

func tick(delta: float, visible: bool) -> Dictionary:
	_transfer_reconsider = false
	if low_cycle.active() and low_cycle.phase != low_cycle.Phase.APPROACH:
		low_cycle.tick(delta, true, visible, transfer.watch_seconds)
		_running = low_cycle.active()
		var fire_request: Dictionary = {"owner": action_id, "mode": &"visible"} if low_cycle.fire_requested() else {}
		var cycle_output := motion(Vector3.ZERO, 1.0, context.last_known_position - actor.global_position, fire_request)
		cycle_output.crouch = low_cycle.crouch_requested()
		return cycle_output
	var direction := Vector3.ZERO
	if transfer.phase == transfer.Phase.RUN_TO_COVER:
		agent.target_position = transfer.cover_detour_position if transfer.cover_detour_active else transfer.hide_position
	elif transfer.phase == transfer.Phase.PEEK_OUT:
		agent.target_position = transfer.peek_position
	if transfer.phase != transfer.Phase.HIDE:
		direction = transfer.step(delta, visible)
	_running = transfer.is_active()
	if low_cycle.active(): low_cycle.tick(delta, transfer.phase == transfer.Phase.HIDE, visible, transfer.watch_seconds)
	var facing: Vector3 = context.last_known_position - actor.global_position if transfer.covering_retreat or direction.is_zero_approx() else direction
	var firing: Dictionary = {"owner": action_id, "mode": &"visible", "support_intent": true, "pressure_reason": &"retreat"} if transfer.covering_retreat and transfer.phase == transfer.Phase.RUN_TO_COVER else {}
	var output := motion(direction, transfer.movement_multiplier(), facing, firing)
	output.crouch = transfer.wants_crouch()
	return output

func reset() -> void:
	transfer.reset()
	low_cycle.reset()
	_transfer_reconsider = false

func can_interrupt(next: Dictionary, _visible: bool) -> bool:
	# 有效转移执行到底，避免邻近样本轮换不断清空卡住计时和绕行次数。
	var unavailable: bool = low_cycle.active() and (not actor.can_use_firearms() or actor.ammo.is_reloading or actor.ammo.magazine_rounds <= 0)
	return next.get("urgent", false) or _transfer_reconsider or unavailable or (not low_cycle.committed() and transfer.phase != transfer.Phase.RUN_TO_COVER)

func state_label() -> String:
	return low_cycle.label() if low_cycle.active() else transfer.state_label()

func on_shot_fired() -> void:
	low_cycle.on_shot_fired()

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running:
		_transfer_reconsider = true
		transfer.on_damage_received()
		_running = transfer.is_active()

func route_multiplier() -> float:
	return transfer.run_speed_multiplier

func route_tick(delta: float, _visible: bool) -> Dictionary:
	transfer.timer = maxf(0.0, transfer.timer - delta)
	if transfer.timer <= 0.0: _running = false
	return motion(Vector3.ZERO, route_multiplier())
