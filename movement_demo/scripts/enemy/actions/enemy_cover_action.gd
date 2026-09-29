extends "res://scripts/enemy/actions/enemy_action.gd"

var transfer = preload("res://scripts/enemy/actions/enemy_cover_motion.gd").new()
var _transfer_reconsider := false

func evaluation_channel() -> StringName:
	return &"shelter_geometry"

func setup(shared_context, section: StringName = &"") -> void:
	super.setup(shared_context, section)
	transfer.setup(context, action_id, definition.parameters if definition != null else {})

func configuration_changed() -> void:
	super.configuration_changed()
	transfer.parameters = definition.parameters

func evaluation_points() -> Array:
	return context.spatial.cover_points()

func evaluate_point(point: Variant) -> Dictionary:
	return context.spatial.assess_cover_point(point)

func transfer_candidates() -> Array:
	var destinations: Array = context.spatial.destinations(self)
	if transfer.is_active() and is_instance_valid(transfer.active_cover_body):
		var current := {"hide": transfer.hide_position, "body": transfer.active_cover_body}
		if not destinations.any(func(other): return other.body == current.body and other.hide.is_equal_approx(current.hide)):
			destinations.append(current)
	return destinations

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var threat: Vector3 = context._known_reload_threat()
	if not threat.is_finite() or context.noise_search_origin.is_finite() or actor.move_speed <= 0.0:
		return options
	var horizon: float = context.utility_horizon_seconds
	var information: float = 0.0 if visible else horizon
	for destination in transfer_candidates():
		if not _valid_cover(destination):
			continue
		destination.path = selection._path_to(actor.global_position, destination.hide)
		var route: Dictionary = context.spatial.assess_cover_route(destination.path, threat, transfer.run_speed_multiplier, context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0)
		var exposed: float = route.exposure + context._reload_exposure(destination.hide, threat) * maxf(0.0, horizon - route.seconds)
		var candidate := option(destination, horizon, exposed, maxf(information, horizon - minf(horizon, route.seconds)))
		candidate.conceals = true
		options.append(candidate)
	_assess_peek(threat, information, visible, options)
	return options

func _valid_cover(destination: Dictionary) -> bool:
	return not context.is_utility_destination_blocked(destination.hide) and (not context.avoid_position.is_finite() or context._horizontal_distance_between(destination.hide, context.avoid_position) >= 0.9) and context.spatial.cover_valid(destination)

func _assess_peek(threat: Vector3, information: float, visible: bool, options: Array[Dictionary]) -> void:
	if visible or not transfer.is_active() or not is_instance_valid(transfer.active_cover_body):
		return
	var body = transfer.active_cover_body
	var points: Array[Vector3] = []
	for candidate in body.get_candidates(threat + Vector3.UP * 0.8, actor.global_position):
		for point in candidate.peeks:
			if not points.has(point): points.append(point)
	for point in points:
		if context.is_utility_destination_blocked(point) or context.utility_rejected_attack_points.any(func(previous): return previous.distance_to(point) < 0.25):
			continue
		if not context.is_position_free(point) or not selection.has_clear_line(point + Vector3.UP * 0.8, threat + Vector3.UP * 0.8):
			continue
		var path: PackedVector3Array = selection._path_to(actor.global_position, point)
		if path.is_empty(): continue
		var route: Dictionary = context.spatial.assess_route(context, path, threat, transfer.peek_speed_multiplier, context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0)
		var horizon: float = context.utility_horizon_seconds
		var exposed: float = route.exposure + context._reload_exposure(point, threat) * maxf(0.0, horizon - route.seconds)
		var candidate := option({"hide": transfer.hide_position, "position": point, "body": body, "path": path}, horizon, exposed, information * minf(1.0, route.seconds / horizon))
		candidate.mode = &"peek"
		candidate.conceals = true
		options.append(candidate)

func validate(candidate: Dictionary, visible: bool) -> bool:
	return super.validate(candidate, visible) and (candidate.get("mode") == &"peek" or _valid_cover(candidate.destination))

func begin(candidate: Dictionary, visible: bool) -> bool:
	_transfer_reconsider = false
	candidate.conceals = true
	super.begin(candidate, visible)
	context.utility_suppression_pending = false
	if candidate.get("mode") == &"peek":
		transfer.start_utility_peek(candidate.destination, context._known_reload_threat())
	else:
		transfer.start_reload_transfer(candidate.destination, context._known_reload_threat(), candidate.get("mode") == &"covering_retreat")
	return true

func valid(_visible: bool) -> bool:
	return _running and is_enabled() and transfer.is_active()

func tick(delta: float, visible: bool) -> Dictionary:
	_transfer_reconsider = false
	var direction := Vector3.ZERO
	if transfer.phase == transfer.Phase.RUN_TO_COVER:
		agent.target_position = transfer.cover_detour_position if transfer.cover_detour_active else transfer.hide_position
	elif transfer.phase == transfer.Phase.PEEK_OUT:
		agent.target_position = transfer.peek_position
	if transfer.phase != transfer.Phase.HIDE:
		direction = transfer.step(delta, visible)
	_running = transfer.is_active()
	var facing: Vector3 = context.last_known_position - actor.global_position if transfer.covering_retreat or direction.is_zero_approx() else direction
	var firing: Dictionary = {"owner": action_id, "mode": &"visible", "bypass_steady": true} if transfer.covering_retreat and transfer.phase == transfer.Phase.RUN_TO_COVER else {}
	return motion(direction, transfer.movement_multiplier(), facing, firing)

func reset() -> void:
	transfer.reset()
	_transfer_reconsider = false

func can_interrupt(next: Dictionary, _visible: bool) -> bool:
	# 有效转移执行到底，避免邻近样本轮换不断清空卡住计时和绕行次数。
	return next.get("urgent", false) or _transfer_reconsider or transfer.phase != transfer.Phase.RUN_TO_COVER

func state_label() -> String:
	return transfer.state_label()

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running:
		_transfer_reconsider = true
		transfer.on_damage_received()
		_running = transfer.is_active()
