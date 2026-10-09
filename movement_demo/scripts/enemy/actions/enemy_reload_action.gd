extends "res://scripts/enemy/actions/enemy_action.gd"

var transfer = preload("res://scripts/enemy/actions/enemy_cover_motion.gd").new()
var _reload_claim: Dictionary = {}
var _reload_started := false
var _rounds_at_start := 0

func _proactive_opportunity() -> Dictionary:
	if not context.cooperation_enabled() or not actor.can_use_firearms(): return {}
	if actor.ammo.magazine_rounds <= 0 or actor.ammo.magazine_rounds >= actor.weapon.magazine_capacity: return {}
	var ratio: float = float(actor.ammo.magazine_rounds) / maxf(1.0, actor.weapon.magazine_capacity)
	if ratio > float(context.setting(&"cooperation", &"reload_rounds_ratio", 0.35)): return {}
	var opportunity: Dictionary = context.cooperation_reload_opportunity()
	if float(opportunity.get("support_seconds", 0.0)) < float(context.setting(&"cooperation", &"reload_min_support_seconds", 0.5)): return {}
	return opportunity

func _can_offer_reload() -> bool:
	if not actor.can_use_firearms(): return false
	if actor.ammo.is_reloading or _running: return true
	if not actor.ammo.can_reload(): return false
	return actor.ammo.magazine_rounds == 0 or _proactive_opportunity().get("allowed", false)

func _reload_seconds() -> float:
	# 公共 _reload_seconds 表示当前开火被换弹阻止的时间；余弹主动方案另算其真实耗时。
	if _running and not actor.ammo.is_reloading and _reload_completed(): return 0.0
	return maxf(0.1, actor.weapon.reload_seconds) * (1.0 - actor.ammo.reload_progress)

func _reload_completed() -> bool:
	return actor.ammo.magazine_rounds > 0 and (not plan.get("proactive_reload", false) or (_reload_started and actor.ammo.magazine_rounds > _rounds_at_start) or actor.ammo.magazine_rounds >= actor.weapon.magazine_capacity)

func _mode(candidate: Dictionary) -> StringName:
	return candidate.get("reload_mode", candidate.get("plan", &""))

func _release_reload_claim() -> void:
	if context != null and not _reload_claim.is_empty(): context.cooperation_release(_reload_claim)
	_reload_claim = {}

func setup(shared_context, section: StringName = &"") -> void:
	super.setup(shared_context, section)
	transfer.setup(context, action_id)

func evaluation_points() -> Array:
	if not actor.can_use_firearms() or not context.can_use_action(&"cover"): return []
	# 常驻几何队列保证弹匣刚打空、尚未开始换弹时也能立刻评估。
	# cover_points 在本轮空间准备中共享几何；满匣 evaluate_point 不做物理查询。
	var points: Array = context.spatial.cover_points()
	var origin: Vector3 = actor.global_position
	points.sort_custom(func(a, b): return origin.distance_squared_to(a.hide) < origin.distance_squared_to(b.hide))
	return points

func evaluate_point(point: Variant) -> Dictionary:
	if not context.can_use_action(&"cover") or not _can_offer_reload(): return {}
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
	if not _can_offer_reload():
		return result
	var proactive: bool = plan.get("proactive_reload", false) if _running else actor.ammo.magazine_rounds > 0 and not actor.ammo.is_reloading
	var opportunity := _proactive_opportunity() if proactive else {}
	# 已经真正开始的基础换弹可以完成；未开始的主动补弹须保有合法支持机会。
	if proactive and not actor.ammo.is_reloading and not _reload_completed() and not opportunity.get("allowed", false): return result
	var horizon: float = context.utility_horizon_seconds
	var threat: Vector3 = context._known_reload_threat()
	var seconds := _reload_seconds()
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
		candidate.urgent = not proactive
		candidate.conceals = candidate.get("conceals", false) or not candidate.destination.is_empty()
		candidate.outcome.preference_credit = _cover_credit(candidate, here_exposure, threat)
		if proactive:
			candidate.proactive_reload = true
			candidate.reload_mode = candidate.plan
			candidate.plan = StringName("proactive_" + String(candidate.plan))
			var support: float = minf(seconds, minf(horizon, float(opportunity.get("support_seconds", 0.0))))
			# 去掩体后才换弹的方案，只能使用到位后仍存在的真实支援窗口。
			if _mode(candidate) == &"after_cover":
				support = minf(seconds, maxf(0.0, float(opportunity.get("support_seconds", 0.0)) - maxf(0.0, float(candidate.outcome.unavailable_seconds) - seconds)))
			candidate.outcome.cooperation_seconds = clampf(support, 0.0, horizon)
			candidate.cooperation = {"kind": &"reload", "target_id": context.cooperation_target_id(), "provider_id": opportunity.get("provider_id", 0), "request_id": opportunity.get("request_id", 0), "support_seconds": 0.0, "quality": 1.0}
	return result

func _destination_candidates(destination: Dictionary, visible: bool, threat: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var horizon: float = context.utility_horizon_seconds
	var seconds := _reload_seconds()
	destination = destination.duplicate()
	destination.path = context.routes.planning_path(actor.global_position, destination.hide)
	if not actor.ammo.is_reloading:
		var moving: Dictionary = context.spatial.assess_cover_route(destination.path, threat, transfer.run_speed_multiplier, 0.0)
		var exposed: float = moving.exposure + _stationary_exposure(destination.hide, threat, maxf(0.0, horizon - moving.seconds), destination.get("crouch", false))
		var information: float = horizon if not visible else maxf(0.0, horizon - moving.seconds)
		result.append(option(destination, moving.seconds + seconds, exposed, information, &"after_cover"))
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
			# 翻越会中断实际换弹，现有支持窗口不足以承诺落地后仍有人掩护。
			# 保留真实个人路线成本，不能把普通走路时的协作收益复制给翻越。
			if candidate.get("proactive_reload", false): candidate.outcome.cooperation_seconds = 0.0
		candidate.outcome.preference_credit = _cover_credit(candidate, here_exposure, threat)
		result.append(candidate)
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	if candidate.get("proactive_reload", false) and not actor.ammo.is_reloading and not _proactive_opportunity().get("allowed", false): return false
	return actor.can_use_firearms() and super.validate(candidate, visible) and (candidate.destination.is_empty() or (context.can_use_action(&"cover") and context.spatial.cover_valid(candidate.destination)))

func begin(candidate: Dictionary, visible: bool) -> bool:
	_release_reload_claim()
	if candidate.get("proactive_reload", false) and not actor.ammo.is_reloading:
		_reload_claim = context.cooperation_claim_reload(maxf(_reload_seconds(), float(candidate.outcome.unavailable_seconds)) + 3.0)
		if _reload_claim.is_empty(): return false
	_rounds_at_start = actor.ammo.magazine_rounds
	_reload_started = actor.ammo.is_reloading
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
	if _mode(candidate) != &"after_cover": _reload_started = actor.request_reload() or _reload_started
	return true

func valid(_visible: bool) -> bool:
	# 已经开始的身体换弹可以收尾；途中尚未开始时，支持消失立即重新决策。
	if plan.get("proactive_reload", false) and not actor.ammo.is_reloading and not _reload_completed() and not _proactive_opportunity().get("allowed", false): return false
	return _running and actor.can_use_firearms() and (plan.destination.is_empty() or (context.can_use_action(&"cover") and transfer.is_active()))

func tick(delta: float, visible: bool) -> Dictionary:
	var arrived: bool = plan.destination.is_empty() or transfer.phase == transfer.Phase.HIDE
	var proactive: bool = plan.get("proactive_reload", false)
	var completed := _reload_completed()
	if arrived and not actor.ammo.is_reloading and completed:
		_running = false
		_release_reload_claim()
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
	if arrived and (actor.ammo.magazine_rounds == 0 or proactive) and not actor.ammo.is_reloading:
		_reload_started = actor.request_reload() or _reload_started
	var facing: Vector3 = direction if not direction.is_zero_approx() else context.last_known_position - actor.global_position
	var output := motion(direction, transfer.movement_multiplier() if not plan.destination.is_empty() else 1.0, facing)
	if plan.destination.is_empty() and not plan.get("crouch", false) and _crouch_cover_here(context._known_reload_threat()) != null:
		plan.crouch = true
	output.crouch = transfer.wants_crouch() if not plan.destination.is_empty() else plan.get("crouch", actor.is_crouching())
	return output

func reset() -> void:
	_release_reload_claim()
	_reload_started = false
	transfer.reset()

func state_label() -> String:
	var travelling: bool = not plan.get("destination", {}).is_empty() and transfer.phase != transfer.Phase.HIDE
	if actor.ammo.is_reloading:
		# 身体显示实际进度，此处只描述与换弹同时进行的移动。
		return "前往掩体" if travelling else "原地停留"
	if actor.ammo.magazine_rounds > 0:
		if plan.get("proactive_reload", false) and not _reload_started: return "前往掩体，协调补弹" if travelling else "协调补弹"
		return "换弹完成，继续前往掩体" if travelling else "换弹完成"
	return "前往掩体，准备换弹" if travelling else "准备换弹"

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running and not plan.destination.is_empty():
		transfer.on_damage_received()
		_running = transfer.is_active()

func route_multiplier() -> float:
	return minf(transfer.run_speed_multiplier, 1.0)

func route_tick(delta: float, _visible: bool) -> Dictionary:
	if _mode(plan) == &"on_way" and route_motion.stage == 2 and not actor.ammo.is_reloading:
		_reload_started = actor.request_reload() or _reload_started
	transfer.timer = maxf(0.0, transfer.timer - delta)
	if transfer.timer <= 0.0: _running = false
	return motion(Vector3.ZERO, route_multiplier())
