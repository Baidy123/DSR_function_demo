extends "res://scripts/enemy/actions/enemy_action.gd"

const Approach = preload("res://scripts/enemy/services/enemy_melee_approach.gd")

func collect_candidates(visible: bool) -> Array[Dictionary]:
	if not visible: return []
	var candidates := _contact_candidates()
	for candidate in candidates:
		candidate.outcome = Approach.contact_outcome(context, candidate.contact_path)
	return candidates

func _contact_candidates() -> Array[Dictionary]:
	# Keep a valid side post while following it instead of rotating the side
	# with every target update. Reservations remain part of the normal choice.
	if _running and plan.get("mode") == &"contact_detour" and Approach.contact_position_valid(context, plan.destination.position):
		var continuing: PackedVector3Array = selection._path_to(actor.global_position, plan.destination.position).duplicate()
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
	var candidate := option({"position": path[-1], "path": path} if detour else {}, 0.0, 0.0)
	candidate.route_target = path[-1]
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
