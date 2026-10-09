extends "res://scripts/enemy/actions/enemy_action.gd"

const NEARBY_ENGAGEMENT_RADII := [0.5, 1.0]
const NEARBY_ENGAGEMENT_DIRECTIONS := 8

## 远程接敌组织站定射击、移动与近战推开方案；执行计时分别由射击／近战服务持有。
var ranged_min_distance: float:
	get: return _setting(&"ranged_min_distance", 4.0)
	set(value): _set_setting(&"ranged_min_distance", value)
## 远程期望距离上限（米）；与下限共同决定射击候选点的采样范围。
var ranged_max_distance: float:
	get: return _setting(&"ranged_max_distance", 6.0)
	set(value): _set_setting(&"ranged_max_distance", value)
## 选位有冷却，且有效目标会继续沿用，避免频繁左右换路。
var ranged_repath_seconds: float:
	get: return _setting(&"ranged_repath_seconds", 0.75)
	set(value): _set_setting(&"ranged_repath_seconds", value)
var ranged_repath_timer: float = 0.0
var ranged_has_destination: bool = false
var _move_waypoint := Vector3.INF
var _move_best_distance := INF
var _move_stuck_seconds := 0.0
var _melee_requested := false






func get_engagement_candidate_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not is_enabled() or context.combat_type != context.CombatType.RANGED or not actor.can_use_firearms():
		return points
	if not context.last_known_position.is_finite() or NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return points
	var band: Vector2 = _ranged_distance_band()
	points.append(actor.global_position)
	# 墙角可能只需挪半步就有射界；只采目标周围的大圆环会漏掉这些近点。
	# 这里只生成候选，距离带、身体空间、路径和完整射界仍由同一入口验证。
	for offset_distance: float in NEARBY_ENGAGEMENT_RADII:
		for index in range(NEARBY_ENGAGEMENT_DIRECTIONS):
			var angle := TAU * float(index) / NEARBY_ENGAGEMENT_DIRECTIONS
			points.append(actor.global_position + Vector3(cos(angle), 0.0, sin(angle)) * offset_distance)
	# 保留已经评分的目标，避免角色移动后环形采样变化导致目的地无故消失。
	if not agent.target_position.is_equal_approx(actor.global_position):
		points.append(agent.target_position)
	var radial: Vector3 = actor.global_position - context.last_known_position
	radial.y = 0.0
	if radial.is_zero_approx():
		radial = Vector3.BACK
	var start_angle: float = atan2(radial.z, radial.x)
	for radius: float in [(band.x + band.y) * 0.5, band.y - 0.25]:
		for index in range(16):
			var angle: float = start_angle + TAU * float(index) / 16.0
			var sample: Vector3 = context.last_known_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), sample)
			if context._horizontal_distance_between(sample, nav_point) > 0.75:
				continue
			# 导航网格比地面高，动作目的地始终保存身体脚底高度。
			var point := Vector3(nav_point.x, actor.global_position.y, nav_point.z)
			if not points.has(point):
				points.append(point)
	return points

func assess_engagement_point(point: Vector3, threat: Vector3) -> Dictionary:
	if context.is_utility_destination_blocked(point):
		return {}
	if not is_enabled() or context.combat_type != context.CombatType.RANGED or not actor.can_use_firearms() or not threat.is_finite():
		return {}
	var band: Vector2 = _ranged_distance_band()
	if not _engagement_point_valid(point, band, threat):
		return {}
	var path: PackedVector3Array = context.routes.planning_path(actor.global_position, point)
	if path.is_empty():
		return {}
	var current_distance: float = context._horizontal_distance(threat)
	if current_distance < band.x and not _retreat_path_is_safe(path, current_distance, threat):
		return {}
	return {"position": point, "path": path}

func _engagement_point_valid(point: Vector3, band: Vector2, threat: Vector3 = Vector3.INF) -> bool:
	if not threat.is_finite():
		threat = context.last_known_position
	if not point.is_finite() or actor.weapon == null:
		return false
	var distance: float = context._horizontal_distance_between(point, threat)
	var current_distance: float = context._horizontal_distance(threat)
	var committed: bool = _running and plan.get("destination", {}).get("position", Vector3.INF).distance_to(point) < 0.05 and distance >= current_distance - 0.05
	# 被逼近时允许先退半步，不能要求一步到达完整距离带才承认退路。
	if distance > band.y or (distance < band.x and not committed and distance < current_distance + 0.2):
		return false
	if point.distance_to(threat) > maxf(context.perception.sight_distance, context.perception.close_awareness_radius):
		return false
	var shot_origin: Vector3 = actor.get_posture_muzzle_position(false, point)
	var target: Vector3 = context.known_target_point(threat)
	var shared: Dictionary = context.fresh_shared_contact()
	if not shared.is_empty():
		if context.shared_contact_information(point, 0.0, shared) >= context.utility_horizon_seconds: return false
		if shared.get("aim_position", Vector3.INF).is_finite(): target = shared.aim_position
	return (shot_origin.distance_to(target) <= actor.weapon.fire_range
		and context.is_position_free(point)
		and context.fire.has_clear_firing_lane(shot_origin, target - shot_origin, shot_origin.distance_to(target)))


func is_engagement_destination_valid(destination: Dictionary, check_path: bool = true) -> bool:
	if not destination.has("position") or not is_enabled() or context.combat_type != context.CombatType.RANGED or not actor.can_use_firearms():
		return false
	var band: Vector2 = _ranged_distance_band()
	if not _engagement_point_valid(destination.position, band):
		return false
	if not check_path:
		return true
	var path: PackedVector3Array = context.routes.planning_path(actor.global_position, destination.position)
	if path.is_empty():
		return false
	var distance: float = context._horizontal_distance(context.last_known_position)
	return distance >= band.x or _retreat_path_is_safe(path, distance)


## 只执行评分器选定的位置；条件失效时停下并交还AI，禁止内部另选一个目标。

func step_evaluated_engagement(destination: Dictionary, delta: float, sees_player: bool) -> Vector3:
	ranged_repath_timer = maxf(0.0, ranged_repath_timer - delta)
	var recheck_path: bool = not ranged_has_destination or ranged_repath_timer <= 0.0
	var shared_approach: bool = plan.get("plan", &"") == &"shared_contact" and not context.fresh_shared_contact().is_empty()
	if (not sees_player and not shared_approach) or not is_engagement_destination_valid(destination, recheck_path):
		ranged_has_destination = false
		context.invalidate_utility()
		return Vector3.ZERO
	if recheck_path:
		ranged_repath_timer = maxf(0.1, ranged_repath_seconds)
	var point: Vector3 = destination.position
	if not agent.target_position.is_equal_approx(point):
		agent.target_position = point
	ranged_has_destination = true
	var distance: float = context._horizontal_distance(point)
	if distance <= 0.12:
		reset_movement_progress()
		context.state = context.State.HOLD_POSITION
		if context._horizontal_distance(context.last_known_position) < _ranged_distance_band().x:
			_running = false
		return Vector3.ZERO
	context.state = context.State.REPOSITION
	var next: Vector3 = agent.get_next_path_position()
	# 导航通常提前停在容差范围，末段仍走向选中的脚底位置。
	if distance <= 0.7 and _engagement_final_segment_clear(point):
		next = point
	elif agent.is_navigation_finished():
		ranged_has_destination = false
		context.block_utility_destination(point)
		_running = false
		return Vector3.ZERO
	# 动态身体不会改变烘焙导航；需要按实际靠近拐点的进展判断，不能只检查路径存在。
	var waypoint_distance: float = context._horizontal_distance(next)
	if not _move_waypoint.is_finite() or context._horizontal_distance_between(next, _move_waypoint) > 0.25:
		_move_waypoint = next
		_move_best_distance = INF
	if waypoint_distance < _move_best_distance - 0.05:
		_move_best_distance = waypoint_distance
		_move_stuck_seconds = 0.0
	else:
		_move_stuck_seconds += maxf(0.0, delta)
	if _move_stuck_seconds >= 2.0:
		context.block_utility_destination(point)
		_running = false
		reset_movement_progress()
		return Vector3.ZERO
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * delta))

func _engagement_final_segment_clear(point: Vector3) -> bool:
	var count: int = maxi(1, ceili(context._horizontal_distance(point) / 0.1))
	for index in range(1, count + 1):
		if not context.is_position_free(actor.global_position.lerp(point, float(index) / count), true):
			return false
	return true


# 旧测试入口保留；统一评分后的正常接敌使用 step_evaluated_engagement。

func _ranged_distance_band() -> Vector2:
	var minimum = maxf(1.0, ranged_min_distance)
	return Vector2(minimum, maxf(minimum + 1.0, ranged_max_distance))

func _retreat_path_is_safe(path: PackedVector3Array, current_distance: float, known_position: Vector3 = Vector3.INF) -> bool:
	if not known_position.is_finite():
		known_position = context.last_known_position
	var threat = Vector2(known_position.x, known_position.z)
	var previous = Vector2(actor.global_position.x, actor.global_position.z)
	for point in path:
		var next = Vector2(point.x, point.z)
		var closest = Geometry2D.get_closest_point_to_segment(threat, previous, next)
		if closest.distance_to(threat) < maxf(0.1, current_distance - 0.2):
			return false
		previous = next
	return true

func reset_movement_progress() -> void:
	_move_waypoint = Vector3.INF
	_move_best_distance = INF
	_move_stuck_seconds = 0.0

func reset() -> void:
	ranged_has_destination = false
	ranged_repath_timer = 0.0
	_melee_requested = false
	reset_movement_progress()

func evaluation_points() -> Array:
	return get_engagement_candidate_points() if context.sees_player or not context.fresh_shared_contact().is_empty() else []

func evaluation_weight() -> int:
	return 1

func evaluation_priority_count() -> int:
	return 1 + NEARBY_ENGAGEMENT_RADII.size() * NEARBY_ENGAGEMENT_DIRECTIONS

func evaluate_point(point: Variant) -> Dictionary:
	var candidate := assess_engagement_point(point, context.last_known_position)
	if candidate.is_empty():
		return {}
	var visible: bool = context.sees_player
	var route: Dictionary = context.spatial.assess_route(context, candidate.path, context.last_known_position, 1.0, context.spatial._reload_seconds(context), visible)
	var exposed: float = route.exposure + context._reload_exposure(candidate.position, context.last_known_position) * maxf(0.0, context.utility_horizon_seconds - route.seconds)
	if not visible:
		var information: float = context.shared_contact_information(candidate.position, route.seconds)
		return {"destination": candidate, "cost": context.spatial.score(context.utility_horizon_seconds, exposed, information)}
	return {"destination": candidate, "cost": context.spatial.score(maxf(route.seconds - route.fire_seconds, context.spatial._ammo_wait(context)), exposed)}

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_enabled():
		return result
	if not visible: return _shared_contact_candidates()
	if _running and plan.get("plan") == &"melee" and _melee_requested and context.melee.is_active_for(action_id):
		return [plan]
	var can_melee: bool = context.melee.can_request(visible)
	var melee_facts := _melee_facts() if can_melee else {}
	if can_melee:
		result.append(_melee_option({}, melee_facts))
	# 空装备、兵种切换卸装或关闭射击时不评估枪械方案；有效近战方案仍保留。
	if not actor.can_use_firearms():
		return result
	var threat: Vector3 = context.last_known_position
	var horizon: float = context.utility_horizon_seconds
	var target: Vector3 = context.known_target_point(threat)
	var origin: Vector3 = actor.get_shot_origin()
	var wait: float = context.spatial._ammo_wait(context)
	var ammo_wait := wait
	var reload_seconds: float = context.spatial._reload_seconds(context)
	if origin.distance_to(target) > actor.weapon.fire_range or not context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
		wait = horizon
	result.append(option({}, wait, context._reload_exposure(actor.global_position, threat) * horizon))
	var destinations: Array = context.spatial.destinations(self)
	if _running and not plan.get("destination", {}).is_empty():
		destinations.append(plan.destination)
	var checked_points: Dictionary = {}
	for destination in destinations:
		# Preserve all candidates, including the running plan, while validating an
		# exactly repeated position only once in this synchronous collection.
		if not checked_points.has(destination.position):
			checked_points[destination.position] = assess_engagement_point(destination.position, threat)
		var checked: Dictionary = checked_points[destination.position].duplicate()
		if checked.is_empty():
			continue
		var route: Dictionary = context.spatial.assess_route(context, checked.path, threat, 1.0, reload_seconds, true)
		result.append(option(checked, maxf(route.seconds - route.fire_seconds, ammo_wait), route.exposure + context._reload_exposure(checked.position, threat) * maxf(0.0, horizon - route.seconds)))
		if can_melee:
			result.append(_melee_option(checked, melee_facts))
	return result

func _shared_contact_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var report: Dictionary = context.fresh_shared_contact()
	if report.is_empty() or not actor.can_use_firearms(): return result
	var threat: Vector3 = report.position
	var horizon: float = context.utility_horizon_seconds
	var destinations: Array = context.spatial.destinations(self)
	if _running and plan.get("plan", &"") == &"shared_contact" and not plan.get("destination", {}).is_empty(): destinations.append(plan.destination)
	var checked_points := {}
	for destination: Dictionary in destinations:
		if checked_points.has(destination.position): continue
		checked_points[destination.position] = true
		var checked := assess_engagement_point(destination.position, threat)
		if checked.is_empty(): continue
		var route: Dictionary = context.spatial.assess_route(context, checked.path, threat, 1.0, 0.0, false)
		var information: float = context.shared_contact_information(checked.position, route.seconds, report)
		if information >= horizon: continue
		var exposure: float = route.exposure + context._reload_exposure(checked.position, threat) * maxf(0.0, horizon - route.seconds)
		var candidate := option(checked, horizon, exposure, information, &"shared_contact")
		candidate.target_id = report.target_id
		candidate.known_position = threat
		candidate.combat_contact = true
		result.append(candidate)
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	if candidate.get("plan", &"") == &"shared_contact":
		return _shared_plan_authorized(candidate, visible) and is_engagement_destination_valid(candidate.destination)
	if candidate.get("plan") == &"melee":
		return is_enabled() and context.melee.can_request(visible)
	return is_enabled() and visible and actor.can_use_firearms() and (candidate.destination.is_empty() or is_engagement_destination_valid(candidate.destination))

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	reset()
	context.state = context.State.REPOSITION
	agent.target_position = candidate.destination.get("position", actor.global_position)
	return true

func valid(visible: bool) -> bool:
	if plan.get("plan", &"") == &"shared_contact": return _running and _shared_plan_authorized(plan, visible)
	if _running and is_enabled() and visible and plan.get("plan") == &"melee":
		return context.melee.is_active_for(action_id) if _melee_requested else context.melee.can_request(visible)
	return _running and is_enabled() and visible and actor.can_use_firearms()

func _shared_plan_authorized(candidate: Dictionary, visible: bool) -> bool:
	if not is_enabled() or visible or not actor.can_use_firearms(): return false
	var report: Dictionary = context.fresh_shared_contact()
	return not report.is_empty() and candidate.get("target_id", 0) == report.target_id and candidate.get("known_position", Vector3.INF).distance_to(report.position) <= 0.5 and not candidate.get("destination", {}).is_empty()

func tick(delta: float, visible: bool) -> Dictionary:
	if plan.get("plan", &"") == &"shared_contact":
		if not valid(visible):
			_running = false
			return motion(Vector3.ZERO)
		var direction := step_evaluated_engagement(plan.destination, delta, false)
		# Even an unobstructed expected firing position is only an approach until
		# this observer personally reacquires the target through normal perception.
		return motion(direction, 1.0, plan.known_position - actor.global_position)
	if plan.get("plan") == &"melee":
		context.state = context.State.HOLD_POSITION
		if _melee_requested and not context.melee.is_active_for(action_id):
			_running = false
			return motion(Vector3.ZERO)
		_melee_requested = true
		var retreat := Vector3.ZERO
		# 查询执行许可后退让；控制器维护计时，身体处理实际命中与能力冲突。
		if context.melee.allows_movement(action_id) and not plan.destination.is_empty():
			retreat = step_evaluated_engagement(plan.destination, delta, visible)
			_running = true # 到达或路径失效只停止移动，不能跳过未完成的收招。
		return motion(retreat, 1.0, context.last_known_position - actor.global_position, {}, {"owner": action_id})
	var direction := Vector3.ZERO
	if plan.destination.is_empty():
		context.state = context.State.HOLD_POSITION
	else:
		direction = step_evaluated_engagement(plan.destination, delta, visible)
	return motion(direction, 1.0, Vector3.INF, {"owner": action_id, "mode": &"visible"})

func state_label() -> String:
	if plan.get("plan", &"") == &"shared_contact": return "共享接敌"
	return super.state_label()


func can_interrupt(_next: Dictionary, _visible: bool) -> bool:
	return not context.melee.is_active_for(action_id)


## 这是接敌行为的一个方案，不是新的默认／战术行为；收集只估计结果，不发起攻击。
func _melee_facts() -> Dictionary:
	var settings: Dictionary = context.melee.weapon_settings()
	var horizon: float = context.utility_horizon_seconds
	var occupied: float = minf(horizon, settings.windup + settings.recovery)
	var threat: Vector3 = context.last_known_position
	var away: Vector3 = threat - actor.global_position
	away.y = 0.0
	away = away.normalized()
	var push_distance := _free_melee_push_distance(threat, away, settings.distance)
	# 先估计前摇期间目标的逼近；不能扣掉整个窗口的追近，再把敌人当作一直站着。
	var closing_speed: float = maxf(0.0, -context.observed_velocity.dot(away))
	var retained_distance := maxf(0.0, push_distance - closing_speed * settings.windup)
	var pushed_threat: Vector3 = threat + away * retained_distance
	var before: float = context._reload_exposure(actor.global_position, threat)
	var reload_wait: float = context.spatial._ammo_wait(context)
	if actor.ammo.magazine_rounds == 0 and actor.weapon != null:
		reload_wait = maxf(reload_wait, actor.weapon.reload_seconds)
	var ready: float = occupied + reload_wait
	var windup: float = minf(horizon, settings.windup)
	return {"horizon": horizon, "before": before, "pushed_threat": pushed_threat, "ready": ready, "windup": windup}

func _melee_option(destination: Dictionary = {}, facts: Dictionary = {}) -> Dictionary:
	if facts.is_empty(): facts = _melee_facts()
	var horizon: float = facts.horizon
	var before: float = facts.before
	var pushed_threat: Vector3 = facts.pushed_threat
	var ready: float = facts.ready
	var windup: float = facts.windup
	if destination.is_empty():
		var exposure: float = before * windup + context._reload_exposure(actor.global_position, pushed_threat) * maxf(0.0, horizon - windup)
		return option({}, ready, exposure, 0.0, &"melee")
	# 和直接退让比较同一条已验证路径；近战出手后移动，收招完成后才恢复火力。
	var route: Dictionary = context.spatial.assess_route(context, destination.path, pushed_threat, 1.0, ready, true, windup)
	var exposure: float = before * windup + route.exposure + context._reload_exposure(destination.position, pushed_threat) * maxf(0.0, horizon - route.seconds)
	return option(destination, maxf(ready, route.seconds - route.fire_seconds), exposure, 0.0, &"melee")


func _free_melee_push_distance(threat: Vector3, direction: Vector3, distance: float) -> float:
	if distance <= 0.0 or direction.is_zero_approx(): return 0.0
	# 以可见目标处的角色体积扫出安全距离，不把墙后的空间算作必然收益。
	var collider: CollisionShape3D = actor.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = Transform3D(collider.global_basis, threat + Vector3.UP * (collider.position.y + 0.05))
	query.motion = direction * distance
	query.collision_mask = 1
	query.exclude = [actor.get_rid(), context.player.get_rid()]
	var fractions: PackedFloat32Array = actor.get_world_3d().direct_space_state.cast_motion(query)
	return distance * fractions[0] if not fractions.is_empty() else 0.0
