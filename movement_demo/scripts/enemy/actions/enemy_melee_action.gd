extends "res://scripts/enemy/actions/enemy_action.gd"

const Approach = preload("res://scripts/enemy/services/enemy_melee_approach.gd")
var _contact_route_target := Vector3.INF
var _contact_observation := Vector3.INF

func reset() -> void:
	_contact_route_target = Vector3.INF
	_contact_observation = Vector3.INF

func cancel(reason: StringName = &"switch") -> void:
	var retained_target := _contact_route_target
	var retained_observation := _contact_observation
	super.cancel(reason)
	if reason == &"switch":
		_contact_route_target = retained_target
		_contact_observation = retained_observation

func configuration_changed() -> void:
	super.configuration_changed()
	reset()

func collect_candidates(visible: bool) -> Array[Dictionary]:
	if not visible: return []
	var candidates := _contact_candidates()
	for candidate in candidates:
		candidate.outcome = Approach.contact_outcome(context, candidate.contact_path)
	if candidates.is_empty() and actor.weapon != null and actor.weapon.melee_enabled and actor.can_equip_weapon(actor.weapon):
		# A visible target can be airborne or temporarily lack a prepared path.
		# Keep combat attention while the bounded route queue catches up. This
		# option disappears as soon as a real contact route is available.
		var horizon: float = context.utility_horizon_seconds
		var waiting := option({}, horizon, context._reload_exposure(actor.global_position, context.last_known_position) * horizon)
		waiting.mode = &"await_route"
		candidates.append(waiting)
	return candidates

func _contact_candidates() -> Array[Dictionary]:
	# Keep a valid side post while following it instead of rotating the side
	# with every target update. Reservations remain part of the normal choice.
	if _running and plan.get("mode") == &"contact_detour" and Approach.contact_position_valid(context, plan.destination.position):
		var continuing: PackedVector3Array = context.routes.planning_path(actor.global_position, plan.destination.position).duplicate()
		for index in continuing.size(): continuing[index].y = actor.global_position.y
		if not continuing.is_empty() and _contact_available(continuing[-1]): return [_contact_candidate(continuing, true)]
	var path: PackedVector3Array = Approach.contact_path(context)
	if not path.is_empty() and _contact_available(path[-1]): return [_contact_candidate(path, false)]
	var alternatives: Array[Dictionary] = []
	for alternative: PackedVector3Array in Approach.contact_alternatives(context):
		alternatives.append(_contact_candidate(alternative, true))
	return context.personal_position_choices(alternatives)

func _contact_available(point: Vector3) -> bool:
	var choices: Array[Dictionary] = [{"id": action_id, "route_target": point}]
	return not context.personal_position_choices(choices).is_empty()

func _contact_candidate(path: PackedVector3Array, detour: bool) -> Dictionary:
	var route_target: Vector3 = path[-1]
	# Ground contact leaves a tiny floor clearance. Keep the known floor's
	# height instead of requesting a new crossing for that settling offset.
	if absf(route_target.y - context.last_known_position.y) < 0.05:
		route_target.y = context.last_known_position.y
	# A contact post may remain useful while the observed target moves a little.
	# Keep that exact post, not its old path relabeled as a new destination.
	if not detour:
		var retained_post := false
		if _contact_route_target.is_finite() and _contact_observation.is_finite() and context._horizontal_distance_between(_contact_observation, context.last_known_position) <= 0.5 and Approach.contact_position_valid(context, _contact_route_target):
			var retained: PackedVector3Array = context.routes.planning_path(actor.global_position, _contact_route_target).duplicate()
			if not retained.is_empty():
				for index in retained.size(): retained[index].y = actor.global_position.y
				path = retained
				route_target = _contact_route_target
				retained_post = true
		_contact_route_target = route_target
		if not retained_post: _contact_observation = context.last_known_position
	var candidate := option({"position": path[-1], "path": path} if detour else {}, 0.0, 0.0)
	candidate.route_target = route_target
	candidate.route_priority = true
	candidate.contact_path = path
	if detour: candidate.mode = &"contact_detour"
	return candidate

func validate(candidate: Dictionary, visible: bool) -> bool:
	return is_enabled() and visible and (candidate.get("mode") != &"contact_detour" or Approach.contact_position_valid(context, candidate.destination.position))

func valid(visible: bool) -> bool:
	return _running and validate(plan, visible)

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	context.state = context.State.APPROACH
	return true

func tick(_delta: float, visible: bool) -> Dictionary:
	# 已选中的接近行为只提交基础挥击请求；计时、冷却和命中仍在控制器／身体。
	if context.melee.is_active_for(action_id) or context.melee.can_request(visible):
		return motion(Vector3.ZERO, 1.0, Vector3.INF, {}, {"owner": action_id})
	if plan.get("mode") == &"await_route":
		return motion(Vector3.ZERO, 1.0, context.last_known_position - actor.global_position)
	var target: Vector3 = plan.destination.position if plan.get("mode") == &"contact_detour" else context.last_known_position
	if agent.target_position.distance_to(target) > (0.05 if plan.get("mode") == &"contact_detour" else 0.25):
		agent.target_position = target
	var next: Vector3 = agent.get_next_path_position()
	var stopping_distance: float = float(_setting(&"stopping_distance", 1.3))
	if actor.weapon != null and actor.weapon.melee_enabled:
		stopping_distance = minf(stopping_distance, maxf(0.0, actor.weapon.melee_range - 0.05))
	if (visible and plan.get("mode") != &"contact_detour" and context._horizontal_distance(context.last_known_position) <= stopping_distance) or agent.is_navigation_finished():
		return motion(Vector3.ZERO)
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return motion(direction.normalized())


func can_interrupt(_next: Dictionary, _visible: bool) -> bool:
	return not context.melee.is_active_for(action_id)

func command_roles() -> Array[StringName]:
	return [&"engage", &"guard", &"move"] if actor.weapon != null and actor.weapon.melee_enabled else []
