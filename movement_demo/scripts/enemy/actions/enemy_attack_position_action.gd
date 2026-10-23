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
var _cells_signature := -1
var _cells: Array = []

func command_roles() -> Array[StringName]:
	return [&"engage"] if actor.can_use_firearms() else []

func command_default_assignment() -> bool:
	return false

func prepare_command_offers(query: Dictionary, cursor: Dictionary, deadline_usec: int) -> Dictionary:
	if query.objective.phase != &"contact" or not query.body.visible or query.body.reloading or query.body.rounds <= 0:
		return {"done": true, "offers": [], "reason": &"no_visible_attack"}
	var work := cursor.duplicate(true)
	if work.is_empty():
		var regions: Array = context.spatial.regions()
		regions.sort_custom(func(a, b): return query.body.position.distance_squared_to(a.global_position) < query.body.position.distance_squared_to(b.global_position))
		var ids := PackedInt64Array()
		for region in regions: ids.append(region.get_instance_id())
		work = {"regions": ids, "region_index": 0, "positions": PackedVector3Array(), "index": 0, "count": 0, "checked": 0}
	if work.index >= work.positions.size() and work.region_index < work.regions.size():
		var region = instance_from_id(work.regions[work.region_index])
		work.region_index += 1
		work.index = 0
		work.positions = PackedVector3Array()
		if is_instance_valid(region):
			# Refine a bounded nearby batch, not every cell of every cover in one call.
			var cells: Array[Dictionary] = region.get_attack_cells().filter(func(cell): return query.body.position.distance_to(cell.position) <= 10.0)
			cells.sort_custom(func(a, b): return query.body.position.distance_squared_to(a.position) < query.body.position.distance_squared_to(b.position))
			cells = selection.attack_geometry.refine(context, region, context.known_target_point(query.objective.position), cells.slice(0, 24))
			cells.sort_custom(func(a, b): return query.body.position.distance_squared_to(a.position) < query.body.position.distance_squared_to(b.position))
			for cell in cells.slice(0, 32): work.positions.append(cell.position)
		return {"offers": [], "next_cursor": work, "done": false}
	var offers: Array[Dictionary] = []
	if work.index < work.positions.size() and Time.get_ticks_usec() < deadline_usec:
		var point := {"position": work.positions[work.index], "cover_id": work.regions[work.region_index - 1]}
		work.index += 1
		work.checked += 1
		var cover = instance_from_id(point.cover_id)
		if is_instance_valid(cover) and context.navigation_region.is_ancestor_of(cover):
			point.body = cover
			var assessment := _assess_position(point)
			if not assessment.is_empty():
				var site := {"position": point.position, "role": &"engage", "look_position": query.objective.position,
					"prepared_route": assessment.destination.path, "site_key": "attack:%s:%s" % [point.cover_id, point.position]}
				var offer := super.command_site_offer(query, site)
				if not offer.is_empty() and not offer.get("retry_detour", false):
					offer.attack_cover_id = point.cover_id
					offer.estimate = maxf(0.0, float(assessment.unavailable)) + maxf(0.0, float(assessment.exposed))
					offer.tactical.protected = true
					offers.append(offer)
					work.count += 1
	return {"offers": offers, "next_cursor": work, "done": (work.index >= work.positions.size() and work.region_index >= work.regions.size()) or work.count >= 6 or work.checked >= 96}

func validate_command_offer(query: Dictionary, offer: Dictionary) -> Dictionary:
	var result := super.validate_command_offer(query, offer)
	var cover = instance_from_id(offer.get("attack_cover_id", 0))
	result.valid = result.valid and query.body.visible and is_instance_valid(cover) and context.navigation_region.is_ancestor_of(cover)
	if result.valid:
		var target: Vector3 = context.known_target_point(context.last_known_position)
		if cover.is_low_cover(): target = selection.low_cover_attack_target(offer.position, context.known_target_points(context.last_known_position))
		result.valid = target.is_finite() and selection.assess_attack_point(offer.position, cover, target, target).usable
	return result

func begin_command(task: Dictionary) -> bool:
	if not super.begin_command(task): return false
	active_cover = instance_from_id(task.get("attack_cover_id", 0)) as StaticBody3D
	destination = task.position
	_query_target = task.look_position
	_using_hit_memory = false
	_remaining = float(task.get("travel_seconds", 0.0)) + 3.0
	_recheck = 0.0
	phase = Phase.MOVE
	return is_instance_valid(active_cover)

func command_work(delta: float, visible: bool, arrived: bool) -> Dictionary:
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.25
		if not _unusable_reason(actor.global_position if arrived else command.position).is_empty():
			context.report_command(command, &"blocked", {"reason": &"attack_position_invalid"})
			return {}
	if arrived:
		phase = Phase.HOLD
		if not visible:
			context.report_command(command, &"complete")
			return {}
	else:
		_remaining -= delta
		if _remaining <= 0.0:
			context.report_command(command, &"blocked", {"reason": &"attack_position_timeout"})
			return {}
	return {"fire": {"owner": action_id, "mode": &"visible"}} if visible else {}



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
	_query_target = known_position
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
	var target: Vector3 = context.known_target_point(_known_position())
	if active_cover.is_low_cover():
		target = selection.low_cover_attack_target(point, context.known_target_points(_known_position()))
		if not target.is_finite(): return "射界受阻"
	var result: Dictionary = selection.assess_attack_point(point, active_cover, target, target)
	return "" if result.usable else result.reason


func _known_position() -> Vector3:
	return _query_target if _using_hit_memory else context.last_seen_position


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
	if is_instance_valid(active_cover) and active_cover.is_low_cover():
		return ["", "前往半身掩体", "半身掩体后架枪"][phase]
	return ["", "前往墙角攻击位置", "墙角占位射击"][phase]


func evaluation_points() -> Array:
	if not context._known_reload_threat().is_finite() or actor.move_speed <= 0.0: return []
	if _cells_signature != context.spatial._geometry:
		_cells_signature = context.spatial._geometry
		_cells = []
		for region in context.spatial.regions():
			_cells.append_array(region.get_attack_cells())
	# The evaluator owns and clears its work queue during action/lifecycle resets.
	# Share immutable cell dictionaries, never the mutable queue array itself.
	return _cells.duplicate()

func evaluation_weight() -> int:
	return 6

func evaluate_point(point: Variant) -> Dictionary:
	if point.has("depth"):
		# 调度单位保持固定，细分在本区域的预算查询内完成，目标移动不重排扫描队列。
		var source: Array[Dictionary] = [point]
		var best: Dictionary = {}
		for cell in selection.attack_geometry.refine(context, point.body, context.known_target_point(context.last_known_position), source):
			var result := _assess_position(cell)
			if not result.is_empty() and (best.is_empty() or result.cost < best.cost): best = result
		return best
	return _assess_position(point)

func _assess_position(point: Dictionary) -> Dictionary:
	var threat: Vector3 = context.last_known_position
	if not is_instance_valid(point.body) or point.position.distance_to(threat) > maxf(context.perception.sight_distance, context.perception.close_awareness_radius): return {}
	var target: Vector3 = context.known_target_point(threat)
	if point.body.is_low_cover():
		target = selection.low_cover_attack_target(point.position, context.known_target_points(threat))
		if not target.is_finite(): return {}
	var checked: Dictionary = selection.assess_attack_point(point.position, point.body, target, target, false)
	if not checked.usable: return {}
	var path: PackedVector3Array = context.routes.planning_path(actor.global_position, point.position)
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

func route_tick(delta: float, visible: bool) -> Dictionary:
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining <= 0.0 or not valid(visible): _running = false
	return motion(Vector3.ZERO)
