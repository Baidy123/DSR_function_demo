extends "res://scripts/enemy/actions/enemy_action.gd"

const NEARBY_ENGAGEMENT_RADII := [0.5, 1.0]
const NEARBY_ENGAGEMENT_DIRECTIONS := 8

## Ranged engagement: candidates and movement; shared fire timing lives in the fire controller.
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





func get_engagement_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for point: Vector3 in get_engagement_candidate_points():
		var candidate: Dictionary = assess_engagement_point(point, context.last_known_position)
		if not candidate.is_empty():
			candidates.append(candidate)
	return candidates


## 先生成少量原始点，供统一评分器分帧完成空间、射界及路径查询。

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
	var path: PackedVector3Array = context.cover_selection._path_to(actor.global_position, point)
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
	if distance < band.x or distance > band.y:
		return false
	if point.distance_to(threat) > maxf(context.perception.sight_distance, context.perception.close_awareness_radius):
		return false
	var shot_origin: Vector3 = point + actor.get_shot_origin() - actor.global_position
	var target: Vector3 = threat + Vector3.UP * 0.8
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
	var path: PackedVector3Array = context.cover_selection._path_to(actor.global_position, destination.position)
	if path.is_empty():
		return false
	var distance: float = context._horizontal_distance(context.last_known_position)
	return distance >= band.x or _retreat_path_is_safe(path, distance)


## 只执行评分器选定的位置；条件失效时停下并交还AI，禁止内部另选一个目标。

func step_evaluated_engagement(destination: Dictionary, delta: float, sees_player: bool) -> Vector3:
	ranged_repath_timer = maxf(0.0, ranged_repath_timer - delta)
	var recheck_path: bool = not ranged_has_destination or ranged_repath_timer <= 0.0
	if not sees_player or not is_engagement_destination_valid(destination, recheck_path):
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
	if distance <= 0.12 and _engagement_point_valid(actor.global_position, _ranged_distance_band()):
		reset_movement_progress()
		context.state = context.State.HOLD_POSITION
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
		if not context.is_position_free(actor.global_position.lerp(point, float(index) / count)):
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
	reset_movement_progress()

func evaluation_points() -> Array:
	return get_engagement_candidate_points() if context.sees_player else []

func evaluation_weight() -> int:
	return 1

func evaluation_priority_count() -> int:
	return 1 + NEARBY_ENGAGEMENT_RADII.size() * NEARBY_ENGAGEMENT_DIRECTIONS

func evaluate_point(point: Variant) -> Dictionary:
	var candidate := assess_engagement_point(point, context.last_known_position)
	if candidate.is_empty():
		return {}
	var route: Dictionary = context.spatial.assess_route(context, candidate.path, context.last_known_position, 1.0, context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0)
	var exposed: float = route.exposure + context._reload_exposure(candidate.position, context.last_known_position) * maxf(0.0, context.utility_horizon_seconds - route.seconds)
	return {"destination": candidate, "cost": context.spatial.score(maxf(route.seconds, context.spatial._ammo_wait(context)), exposed)}

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not visible:
		return result
	var threat: Vector3 = context.last_known_position
	var horizon: float = context.utility_horizon_seconds
	var target := threat + Vector3.UP * 0.8
	var origin: Vector3 = actor.get_shot_origin()
	var wait: float = context.spatial._ammo_wait(context)
	if origin.distance_to(target) > actor.weapon.fire_range or not context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
		wait = horizon
	result.append(option({}, wait, context._reload_exposure(actor.global_position, threat) * horizon))
	var destinations: Array = context.spatial.destinations(self)
	if _running and not plan.get("destination", {}).is_empty():
		destinations.append(plan.destination)
	for destination in destinations:
		var checked := assess_engagement_point(destination.position, threat)
		if checked.is_empty():
			continue
		var route: Dictionary = context.spatial.assess_route(context, checked.path, threat, 1.0, context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0)
		result.append(option(checked, maxf(route.seconds, context.spatial._ammo_wait(context)), route.exposure + context._reload_exposure(checked.position, threat) * maxf(0.0, horizon - route.seconds)))
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	return is_enabled() and visible and (candidate.destination.is_empty() or is_engagement_destination_valid(candidate.destination))

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	reset()
	context.state = context.State.REPOSITION
	agent.target_position = candidate.destination.get("position", actor.global_position)
	return true

func valid(visible: bool) -> bool:
	return _running and is_enabled() and visible

func tick(delta: float, visible: bool) -> Dictionary:
	var direction := Vector3.ZERO
	if plan.destination.is_empty():
		context.state = context.State.HOLD_POSITION
	else:
		direction = step_evaluated_engagement(plan.destination, delta, visible)
	return motion(direction, 1.0, Vector3.INF, {"owner": action_id, "mode": &"visible"})
