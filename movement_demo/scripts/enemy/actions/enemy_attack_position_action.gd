extends "res://scripts/enemy/actions/enemy_action.gd"

# 主动交火占位，与躲藏／探头动作互斥；只使用评分时已有的真实目击位置。

enum Phase { NONE, MOVE, HOLD }
var phase: Phase = Phase.NONE
var destination: Vector3
var active_cover: StaticBody3D
var _query_target: Vector3
var _using_hit_memory: bool = false
var _recheck: float = 0.0
var _remaining: float = 0.0
var _waypoint: Vector3
var _best_distance: float = INF
var _stuck: float = 0.0



func is_active() -> bool:
	return phase != Phase.NONE


# 取消／复位只清理本动作，不覆盖接管方的导航与决策。
func reset() -> void:
	phase = Phase.NONE
	active_cover = null
	_recheck = 0.0
	_remaining = 0.0
	_stuck = 0.0
	_best_distance = INF
	_using_hit_memory = false


func step(delta: float, sees_player: bool) -> Vector3:
	if not is_active():
		return Vector3.ZERO
	if actor.is_dead or not context.is_arena_active():
		reset()
		return Vector3.ZERO
	if not is_enabled() or actor.weapon == null or context.combat_type != context.CombatType.RANGED:
		_finish(sees_player, "能力关闭、无武器或非远程")
		return Vector3.ZERO
	# 主AI已在本帧更新真实目击；之后即使再失视，也沿用该目击记忆。
	if sees_player:
		_using_hit_memory = false
	# 到位后已经站在实际落脚点，不再用早先的采样目的地决定是否离开。
	if phase == Phase.HOLD:
		if not sees_player:
			_finish(false, "占位后失去真实视线")
		else:
			var reason := _unusable_reason(actor.global_position)
			if not reason.is_empty():
				_finish(true, "实际站位失效：" + reason)
		return Vector3.ZERO
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.25
		var reason := _unusable_reason(destination)
		if not reason.is_empty():
			_finish(sees_player, "前往的目的地失效：" + reason)
			return Vector3.ZERO
	_remaining -= delta
	if _remaining <= 0.0:
		_finish(sees_player, "转移超时")
		return Vector3.ZERO
	var distance: float = context._horizontal_distance(destination)
	if distance <= 0.12:
		# 不能提前停在墙后；实际脚下也必须合格才算完成占位。
		if _usable(actor.global_position):
			if not sees_player:
				_finish(false, "到点仍未看见玩家")
				return Vector3.ZERO
			phase = Phase.HOLD
			actor.agent.target_position = actor.global_position
			if selection.debug_cover_selection:
				print("[AI][攻击占位] 到位，保持射击位置 ", actor.global_position)
			return Vector3.ZERO
		if distance <= 0.02:
			_finish(sees_player, "抵达但实际站位不合格")
			return Vector3.ZERO
	# 来弹／受击可能更新普通导航目标；未进入躲藏时继续当前攻击目的地。
	if actor.agent.target_position.distance_to(destination) > 0.01:
		actor.agent.target_position = destination
	var next: Vector3 = actor.agent.get_next_path_position()
	var finishing: bool = distance <= 0.7 and _final_segment_clear()
	if finishing:
		next = destination
	elif actor.agent.is_navigation_finished():
		_finish(sees_player, "导航提前结束且最后一段不通")
		return Vector3.ZERO
	# 卡住时退出本次行动，不持续向同一堵墙走，也不重新抽概率。
	var waypoint_distance: float = context._horizontal_distance(next)
	if context._horizontal_distance_between(next, _waypoint) > 0.25:
		_waypoint = next
		_best_distance = INF
	if waypoint_distance < _best_distance - 0.05:
		_best_distance = waypoint_distance
		_stuck = 0.0
	else:
		_stuck += delta
	if _stuck >= 2.0:
		_finish(sees_player, "路径连续两秒无进展")
		return Vector3.ZERO
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * delta))


## Utility已经比较了具体点与路线；执行该点，不能再按另一套最近距离重选。
func start_evaluated(candidate: Dictionary, known_position: Vector3) -> bool:
	if not is_enabled() or not is_instance_valid(candidate.get("body")):
		return false
	reset()
	destination = candidate.position
	active_cover = candidate.body
	_query_target = known_position + Vector3.UP * 0.8
	_using_hit_memory = true
	if not _usable(destination):
		reset()
		return false
	var length: float = selection._path_length(actor.global_position, destination)
	if not is_finite(length):
		reset()
		return false
	_remaining = length / maxf(0.1, actor.move_speed) + 3.0
	phase = Phase.MOVE
	actor.agent.target_position = destination
	return true


func _usable(point: Vector3) -> bool:
	return _unusable_reason(point).is_empty()


func _unusable_reason(point: Vector3) -> String:
	if not is_instance_valid(active_cover):
		return "所属掩体失效"
	if not _within_sight_range(point, _known_position()):
		return "超过感知距离"
	var target: Vector3 = _known_position() + Vector3.UP * 0.8
	var result: Dictionary = selection.assess_attack_point(point, active_cover, target, target)
	return "" if result.usable else result.reason


func _known_position() -> Vector3:
	return _query_target - Vector3.UP * 0.8 if _using_hit_memory else context.last_seen_position


# 射程够但感知距离不够的点，到位仍不能发现／攻击目标，不作为主动占位目的地。
func _within_sight_range(point: Vector3, known_position: Vector3) -> bool:
	return point.distance_to(known_position) <= maxf(context.perception.sight_distance, context.perception.close_awareness_radius)


func _final_segment_clear() -> bool:
	var count := maxi(1, ceili(context._horizontal_distance(destination) / 0.1))
	for index in range(1, count + 1):
		if not context.is_position_free(actor.global_position.lerp(destination, float(index) / count)):
			return false
	return true


func _finish(sees_player: bool, reason: String = "结束行动") -> void:
	if selection.debug_cover_selection and actor.debug_settings.enabled:
		print("[AI][攻击占位] ", reason)
	var known_position := _known_position()
	if phase == Phase.MOVE and destination.is_finite():
		context.block_utility_destination(destination)
	reset()
	_running = false
	context.resume_after_action(sees_player, known_position)


func state_label() -> String:
	return ["", "前往墙角攻击位置", "墙角占位射击"][phase]


func evaluation_points() -> Array:
	var points: Array = []
	if not context._known_reload_threat().is_finite() or actor.move_speed <= 0.0: return points
	for region in context.spatial.regions():
		points.append_array(region.get_attack_cells())
	return points

func evaluation_weight() -> int:
	return 6

func evaluate_point(point: Variant) -> Dictionary:
	if point.has("depth"):
		# 调度单位保持固定，细分在本区域的预算查询内完成，目标移动不重排扫描队列。
		var source: Array[Dictionary] = [point]
		var best: Dictionary = {}
		for cell in selection.attack_geometry.refine(context, point.body, context.last_known_position + Vector3.UP * 0.8, source):
			var result := _assess_position(cell)
			if not result.is_empty() and (best.is_empty() or result.cost < best.cost): best = result
		return best
	return _assess_position(point)

func _assess_position(point: Dictionary) -> Dictionary:
	var threat: Vector3 = context.last_known_position
	if not is_instance_valid(point.body) or point.position.distance_to(threat) > maxf(context.perception.sight_distance, context.perception.close_awareness_radius): return {}
	var target := threat + Vector3.UP * 0.8
	var checked: Dictionary = selection.assess_attack_point(point.position, point.body, target, target)
	if not checked.usable: return {}
	var path: PackedVector3Array = selection._path_to(actor.global_position, point.position)
	if path.is_empty(): return {}
	var route: Dictionary = context.spatial.assess_route(context, path, threat, 1.0, context.spatial._reload_seconds(context), context.sees_player)
	var remaining: float = maxf(0.0, context.utility_horizon_seconds - route.seconds)
	var exposed: float = route.exposure + context._reload_exposure(point.position, threat, checked.protection) * remaining
	var unavailable: float = maxf(route.seconds - route.fire_seconds, context.spatial._ammo_wait(context)) + remaining * (1.0 - checked.fire_quality)
	return {"destination": {"position": point.position, "body": point.body, "path": path}, "unavailable": unavailable,
		"exposed": exposed, "cost": context.spatial.score(unavailable, exposed)}

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not visible or actor.move_speed <= 0.0: return result
	var assessments: Array = context.spatial.assessments(self)
	if is_active(): assessments.append(evaluate_point({"position": destination, "body": active_cover}))
	for assessment: Dictionary in assessments:
		if assessment.is_empty(): continue
		var candidate: Dictionary = assessment.destination
		if context.is_utility_destination_blocked(candidate.position) or not is_instance_valid(candidate.body): continue
		result.append(option(candidate, maxf(assessment.unavailable, context.spatial._ammo_wait(context)), assessment.exposed))
	return result

func validate(candidate: Dictionary, visible: bool) -> bool:
	return visible and super.validate(candidate, visible) and not evaluate_point(candidate.destination).is_empty()

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	_running = start_evaluated(candidate.destination, context.last_known_position)
	return _running

func valid(visible: bool) -> bool:
	return _running and is_active() and visible and actor.can_use_firearms()

func tick(delta: float, visible: bool) -> Dictionary:
	var direction := step(delta, visible)
	context.state = context.State.HOLD_POSITION if phase == Phase.HOLD else context.State.REPOSITION
	_running = is_active()
	return motion(direction, 1.0, Vector3.INF, {"owner": action_id, "mode": &"visible"})
