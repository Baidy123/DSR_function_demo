extends "res://scripts/enemy/actions/enemy_action.gd"

var transfer = preload("res://scripts/enemy/actions/enemy_cover_motion.gd").new()

func setup(shared_context, section: StringName = &"") -> void:
	super.setup(shared_context, section)
	transfer.setup(context, action_id)

func evaluation_points() -> Array:
	if not actor.can_use_firearms() or not context.can_use_action(&"cover"): return []
	# 常驻几何队列保证弹匣刚打空、尚未开始换弹时也能立刻评估。
	# cover_points 在本轮空间准备中共享几何；满匣 evaluate_point 不做物理查询。
	var points: Array = context.spatial.cover_points()
	points.sort_custom(func(a, b): return actor.global_position.distance_squared_to(a.hide) < actor.global_position.distance_squared_to(b.hide))
	return points

func evaluate_point(point: Variant) -> Dictionary:
	if not actor.can_use_firearms() or not context.can_use_action(&"cover") or (actor.ammo.magazine_rounds > 0 and not actor.ammo.is_reloading): return {}
	var assessment: Dictionary = context.spatial.assess_cover_point(point)
	if assessment.is_empty(): return {}
	var threat: Vector3 = context._known_reload_threat()
	var here_crouch: bool = _crouch_cover_here(threat) != null or actor.is_crouching()
	var here_exposure := _stationary_exposure(actor.global_position, threat, context.utility_horizon_seconds, here_crouch, true)
	var best := INF
	for candidate in _destination_candidates(assessment.destination, context.sees_player, threat):
		var outcome: Dictionary = candidate.outcome
		var credit := _cover_credit(candidate, here_exposure, threat)
		var cost: float = preload("res://scripts/enemy/enemy_utility_score.gd").score_outcome(context, outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss, credit).cost
		best = minf(best, cost)
	assessment.cost = best
	return assessment

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not actor.can_use_firearms() or (actor.ammo.magazine_rounds > 0 and not actor.ammo.is_reloading and not _running):
		return result
	var horizon: float = context.utility_horizon_seconds
	var threat: Vector3 = context._known_reload_threat()
	var seconds: float = context.spatial._reload_seconds(context)
	var crouch_cover: Object = _crouch_cover_here(threat)
	var crouch_here: bool = crouch_cover != null or actor.is_crouching()
	var here_exposure := _stationary_exposure(actor.global_position, threat, horizon, crouch_here, true)
	var here := option({}, seconds, here_exposure, 0.0, &"here")
	here.crouch = crouch_here
	here.conceals = crouch_cover != null
	result.append(here)
	if context.can_use_action(&"cover") and threat.is_finite() and not context.noise_search_origin.is_finite():
		var destinations: Array = context.spatial.cover_destinations()
		if _running and not plan.get("destination", {}).is_empty(): destinations.append(plan.destination)
		for destination in destinations:
			if not context.spatial.cover_valid(destination) or context.is_utility_destination_blocked(destination.hide): continue
			if context.avoid_position.is_finite() and context._horizontal_distance_between(destination.hide, context.avoid_position) < 0.9: continue
			# 原地已能实现相同姿态与遮蔽时，只保留 here，避免同点方案相互切换。
			if context._horizontal_distance(destination.hide) <= 0.12 and (not destination.get("crouch", false) or crouch_here): continue
			result.append_array(_destination_candidates(destination, visible, threat))
	for candidate in result:
		candidate.urgent = true
		candidate.conceals = candidate.get("conceals", false) or not candidate.destination.is_empty()
		candidate.outcome.preference_credit = _cover_credit(candidate, here_exposure, threat)
	return result

func _destination_candidates(destination: Dictionary, visible: bool, threat: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var horizon: float = context.utility_horizon_seconds
	var seconds: float = context.spatial._reload_seconds(context)
	destination = destination.duplicate()
	destination.path = context.routes.planning_path(actor.global_position, destination.hide)
	var moving: Dictionary = context.spatial.assess_cover_route(destination.path, threat, transfer.run_speed_multiplier, seconds if actor.ammo.is_reloading else 0.0)
	var exposed: float = moving.exposure + _stationary_exposure(destination.hide, threat, maxf(0.0, horizon - moving.seconds), destination.get("crouch", false))
	var information: float = horizon if not visible else maxf(0.0, horizon - moving.seconds)
	if not actor.ammo.is_reloading: result.append(option(destination, moving.seconds + seconds, exposed, information, &"after_cover"))
	var walking: Dictionary = context.spatial.assess_cover_route(destination.path, threat, transfer.run_speed_multiplier, seconds)
	var walking_exposure: float = walking.exposure + _stationary_exposure(destination.hide, threat, maxf(0.0, horizon - walking.seconds), destination.get("crouch", false))
	result.append(option(destination, maxf(walking.seconds, seconds), walking_exposure, horizon if not visible else maxf(0.0, horizon - walking.seconds), &"on_way"))
	return result

## 只读当前实际站位与已知威胁，不借墙后玩家位置决定蹲姿。
func _crouch_cover_here(threat: Vector3) -> Object:
	if not threat.is_finite() or not context.can_use_action(&"cover"): return null
	var query = selection._ray_query(actor.get_posture_eye_position(true), actor.get_posture_muzzle_position(false, threat))
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return null
	var body: Object = hit.collider
	if not body.has_method("is_low_cover") or not body.is_low_cover() or not context.navigation_region.is_ancestor_of(body): return null
	var box: CollisionShape3D = body.get_node("CollisionShape3D")
	var point := box.to_local(actor.global_position)
	var half: Vector3 = box.shape.size * 0.5
	var width: float = body.wall_gap + body.hide_depth
	if absf(point.x) > half.x + width or absf(point.z) > half.z + width or absf(point.y + half.y) > 0.35: return null
	if not selection._center_hidden_by_cover(actor.global_position, actor.get_posture_eye_position(false, threat), body, true): return null
	if context._reload_exposure(actor.global_position, threat, -1.0, true) >= context._reload_exposure(actor.global_position, threat): return null
	return body

func _stationary_exposure(point: Vector3, threat: Vector3, seconds: float, crouched: bool, here: bool = false) -> float:
	if not threat.is_finite() or seconds <= 0.0: return 0.0
	var standing: float = context._reload_exposure(point, threat)
	if not crouched: return standing * seconds
	var transition: float = maxf(0.0, actor.posture_seconds) * (1.0 - actor.body_motion.amount if here else 1.0)
	transition = minf(seconds, transition)
	return standing * transition + context._reload_exposure(point, threat, -1.0, true) * (seconds - transition)

func _cover_credit(candidate: Dictionary, here_exposure: float, threat: Vector3) -> float:
	if candidate.destination.is_empty() or not threat.is_finite(): return 0.0
	var path: PackedVector3Array = candidate.destination.get("path", PackedVector3Array())
	var route: Dictionary = candidate.get("route", {})
	if not route.is_empty():
		path = route.before.duplicate()
		path.append(route.vault.exit)
		path.append_array(route.after)
	if not context.spatial.cover_route_safe(path, threat): return 0.0
	var distance := 0.0
	var previous: Vector3 = actor.global_position
	for point: Vector3 in path:
		distance += context._horizontal_distance_between(previous, point)
		previous = point
	var limit: float = maxf(0.1, float(_setting(&"reload_cover_preference_distance", 4.0)))
	var nearby := clampf((limit - distance) / (limit * 0.5), 0.0, 1.0)
	var gain := clampf((here_exposure - float(candidate.outcome.exposed_seconds)) / maxf(0.01, context.utility_horizon_seconds), 0.0, 1.0)
	return maxf(0.0, float(_setting(&"reload_cover_preference", 6.0))) * nearby * gain

func expand_route_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	if candidates.is_empty() and route_motion.route.is_empty(): return []
	var result: Array[Dictionary] = []
	var threat: Vector3 = context._known_reload_threat()
	var here_crouch: bool = _crouch_cover_here(threat) != null or actor.is_crouching()
	var here_exposure := _stationary_exposure(actor.global_position, threat, context.utility_horizon_seconds, here_crouch, true)
	for candidate in super.expand_route_candidates(candidates):
		# 翻越展开改变了真实路线与暴露，必须重新门控信用，不能复制普通路线的奖励。
		if not candidate.get("route", {}).is_empty():
			var path: PackedVector3Array = candidate.route.before.duplicate()
			path.append(candidate.route.vault.exit)
			path.append_array(candidate.route.after)
			if not context.spatial.cover_route_safe(path, threat): continue
		candidate.outcome.preference_credit = _cover_credit(candidate, here_exposure, threat)
		result.append(candidate)
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	return actor.can_use_firearms() and super.validate(candidate, visible) and (candidate.destination.is_empty() or (context.can_use_action(&"cover") and context.spatial.cover_valid(candidate.destination)))

func begin(candidate: Dictionary, visible: bool) -> bool:
	candidate.conceals = candidate.get("conceals", false) or not candidate.destination.is_empty()
	super.begin(candidate, visible)
	if candidate.destination.is_empty():
		agent.target_position = actor.global_position
		if not candidate.has("crouch"):
			candidate.crouch = _crouch_cover_here(context._known_reload_threat()) != null or actor.is_crouching()
		actor.request_crouch(candidate.crouch)
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
	var output := motion(direction, transfer.movement_multiplier() if not plan.destination.is_empty() else 1.0, facing)
	if plan.destination.is_empty() and not plan.get("crouch", false) and _crouch_cover_here(context._known_reload_threat()) != null:
		plan.crouch = true
	output.crouch = transfer.wants_crouch() if not plan.destination.is_empty() else plan.get("crouch", actor.is_crouching())
	return output

func reset() -> void:
	transfer.reset()

func state_label() -> String:
	var travelling: bool = not plan.get("destination", {}).is_empty() and transfer.phase != transfer.Phase.HIDE
	if actor.ammo.is_reloading:
		# 身体显示实际进度，此处只描述与换弹同时进行的移动。
		return "前往掩体" if travelling else "原地停留"
	if actor.ammo.magazine_rounds > 0:
		return "换弹完成，继续前往掩体" if travelling else "换弹完成"
	return "前往掩体，准备换弹" if travelling else "准备换弹"

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running and not plan.destination.is_empty():
		transfer.on_damage_received()
		_running = transfer.is_active()

func route_multiplier() -> float:
	return minf(transfer.run_speed_multiplier, 1.0)

func route_tick(delta: float, _visible: bool) -> Dictionary:
	if plan.get("plan") == &"on_way" and route_motion.stage == 2 and not actor.ammo.is_reloading: actor.request_reload()
	transfer.timer = maxf(0.0, transfer.timer - delta)
	if transfer.timer <= 0.0: _running = false
	return motion(Vector3.ZERO, route_multiplier())
