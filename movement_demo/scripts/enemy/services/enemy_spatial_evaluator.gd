extends RefCounted

const EVALUATION_POINTS_PER_FRAME := 24
const EVALUATION_BUDGET_USEC := 2000
const CACHED_DESTINATIONS := 6
const CACHE_LIFETIME_MSEC := 2000
var context
var jobs: Array[Dictionary] = []
var last_evaluation_usec := 0
var last_evaluated_count := 0
var total_evaluated_count := 0
var completed_passes := 0
var _visible := false
var _frame := -1
var _cursor := 0
var _position := Vector3.INF
var _threat := Vector3.INF
var _geometry := 0
var _weapon: Resource
var _reloading := false
var _route_frame := -1
var _route_cache: Dictionary = {}
var _preparing_cover_points := false
var _prepared_cover_points_ready := false
var _prepared_cover_points: Array = []

func register(action) -> void:
	for job in jobs:
		if job.channel == action.evaluation_channel():
			if job.owners.any(func(owner): return owner.get_ref() == action): return
			job.owners.append(weakref(action))
			return
	jobs.append({"owner": weakref(action), "owners": [weakref(action)], "channel": action.evaluation_channel(), "points": [], "cursor": 0, "priority": 0, "priority_cursor": 0, "completed_passes": 0, "cache": []})
	_position = Vector3.INF

## 显式撤销注册，不能依靠旧实例是否还被调试器或其他观察者持有来决定生命周期。
func unregister(action) -> void:
	for index in range(jobs.size() - 1, -1, -1):
		var job := jobs[index]
		job.owners = job.owners.filter(func(owner): return owner.get_ref() != null and owner.get_ref() != action)
		if job.owners.is_empty():
			jobs.remove_at(index)
		else:
			job.owner = job.owners[0]
	_position = Vector3.INF

func reset_evaluation() -> void:
	if context != null: context.routes.reset()
	_route_frame = -1
	_route_cache.clear()
	for job in jobs:
		job.cache.clear()
		job.points.clear()
		job.cursor = 0
		job.completed_passes = 0
		job.priority = 0
	_position = Vector3.INF
	_frame = -1
	last_evaluation_usec = 0
	last_evaluated_count = 0
	total_evaluated_count = 0
	completed_passes = 0

func regions() -> Array:
	return context.get_tree().get_nodes_in_group("cover_region").filter(func(region): return context.navigation_region.is_ancestor_of(region))

func advance_evaluation() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _frame:
		return
	_frame = frame
	var started := Time.get_ticks_usec()
	last_evaluated_count = 0
	# Route geometry shares the same frame budget, rather than running inside candidate collection.
	if context.routes.has_pending() and frame % 4 == 0:
		context.routes.advance_one()
		last_evaluated_count += 1
		total_evaluated_count += 1
	for job in jobs:
		job.owners = job.owners.filter(func(owner): return owner.get_ref() != null and owner.get_ref().is_enabled())
		if not job.owners.is_empty(): job.owner = job.owners[0]
	jobs = jobs.filter(func(job): return not job.owners.is_empty())
	var threat: Vector3 = context._known_reload_threat()
	var geometry: Array = [NavigationServer3D.map_get_iteration_id(context.agent.get_navigation_map())]
	for region in regions():
		var collision: CollisionShape3D = region.get_node("CollisionShape3D")
		geometry.append([region.get_instance_id(), collision.global_transform, collision.shape.size, region.hide_length_ratio, region.short_hide_length_ratio, region.hide_depth, region.wall_gap, region.sample_spacing, region.attack_inner_radius, region.attack_outer_radius, region.attack_sample_spacing, region.low_cover, region.vault_enabled, collision.disabled, region.collision_layer])
	geometry.append([context.actor.get_posture_body_height(false), context.actor.get_posture_body_height(true), context.actor.get_node("CollisionShape3D").shape.radius])
	var signature := hash(geometry)
	if signature != _geometry: context.routes.reset()
	var changed: bool = _visible != context.sees_player or signature != _geometry or not _position.is_finite() or _position.distance_to(context.actor.global_position) > 0.5 or threat != _threat and (not threat.is_finite() or not _threat.is_finite() or threat.distance_to(_threat) > 0.25) or _weapon != context.actor.weapon or _reloading != context.actor.ammo.is_reloading
	if changed:
		var initial: bool = not _position.is_finite() or signature != _geometry
		_visible = context.sees_player
		_geometry = signature
		_position = context.actor.global_position
		_threat = threat
		_weapon = context.actor.weapon
		_reloading = context.actor.ammo.is_reloading
		# Reuse immutable cover geometry only while rebuilding this pass's jobs.
		# Each job receives its own Array; clearing one queue cannot clear another.
		_preparing_cover_points = true
		_prepared_cover_points_ready = false
		for job in jobs:
			job.cache.clear()
			var empty: bool = job.points.is_empty()
			job.points = job.owner.get_ref().evaluation_points()
			job.cursor %= maxi(1, job.points.size())
			if initial or empty:
				job.priority = mini(job.points.size(), job.owner.get_ref().evaluation_priority_count())
				job.priority_cursor = 0
				if job.priority > 0: job.cursor = job.priority % job.points.size()
		_preparing_cover_points = false
		_prepared_cover_points_ready = false
		_prepared_cover_points.clear()
	var queue: Array = []
	for job in jobs:
		if not job.points.is_empty():
			for repeat in maxi(1, job.owner.get_ref().evaluation_weight()):
				queue.append(job)
	while not queue.is_empty() and last_evaluated_count < EVALUATION_POINTS_PER_FRAME and Time.get_ticks_usec() - started < EVALUATION_BUDGET_USEC:
		_cursor %= queue.size()
		var job: Dictionary = queue[_cursor]
		_cursor += 1
		for queued in queue:
			if queued.priority > 0:
				job = queued
				break
		var action = job.owner.get_ref()
		var priority: bool = job.priority > 0
		var index: int = job.cursor
		if job.priority > 0:
			index = job.priority_cursor
			job.priority_cursor += 1
			job.priority -= 1
		else: job.cursor = (job.cursor + 1) % job.points.size()
		var assessment: Dictionary = action.evaluate_point(job.points[index])
		if not priority and job.cursor == 0:
			job.completed_passes += 1
			completed_passes += 1
		if not assessment.is_empty():
			_store_candidate(job.cache, assessment.destination, assessment.cost, assessment)
		last_evaluated_count += 1
		total_evaluated_count += 1
	last_evaluation_usec = Time.get_ticks_usec() - started

func destinations(action) -> Array:
	for job in jobs:
		if job.channel == action.evaluation_channel():
			return _cached_destinations(job.cache)
	return []

## 已在预算内完成的几何结果；候选收集只重算共同代价，提交执行时再精确复核。
func assessments(action) -> Array:
	for job in jobs:
		if job.channel == action.evaluation_channel():
			_prune_cache(job.cache)
			return job.cache.map(func(entry): return entry.assessment)
	return []

func cached_candidate_count() -> int:
	var count := 0
	for job in jobs:
		_prune_cache(job.cache)
		count += job.cache.size()
	return count

func score(unavailable: float, exposed: float, information: float = 0.0) -> float:
	return preload("res://scripts/enemy/enemy_utility_score.gd").score_outcome(context, unavailable, exposed, information).cost


func cover_destinations() -> Array:
	var result: Array = []
	for job in jobs:
		for destination in _cached_destinations(job.cache):
			if destination.has("hide") and not result.any(func(other): return other.body == destination.body and other.hide.is_equal_approx(destination.hide)):
				result.append(destination)
	return result

func cover_valid(destination: Dictionary) -> bool:
	var threat: Vector3 = context._known_reload_threat()
	if not threat.is_finite() or not is_instance_valid(destination.get("body")) or not context.is_position_free(destination.hide):
		return false
	if not context.cover_selection._center_hidden_by_cover(destination.hide, context.actor.get_posture_eye_position(false, threat), destination.body, destination.get("crouch", false)):
		return false
	var path: PackedVector3Array = context.routes.planning_path(context.actor.global_position, destination.hide)
	return cover_route_safe(path, threat)

## 撤向掩体不能穿过已知威胁的近身范围；已在近处时仍允许向外脱离。
## 只使用感知/受击记忆，不查询隐藏玩家的实时坐标。
func cover_route_safe(path: PackedVector3Array, threat: Vector3) -> bool:
	if path.is_empty(): return false
	var start_distance: float = context._horizontal_distance_between(context.actor.global_position, threat)
	var nearest: float = context.cover_selection._minimum_path_distance_to_threat(path, threat)
	return nearest >= minf(1.5, start_distance) - 0.1

func assess_cover_route(path: PackedVector3Array, threat: Vector3, multiplier: float, reload_seconds: float, evaluate_fire: bool = false) -> Dictionary:
	var route := assess_route(context, path, threat, multiplier, reload_seconds, evaluate_fire).duplicate()
	var start_distance: float = context._horizontal_distance_between(context.actor.global_position, threat)
	var nearest: float = context.cover_selection._minimum_path_distance_to_threat(path, threat)
	# 把主动接近威胁折算为额外暴露时间，仍由共同风险权重决定是否值得。
	var approach := clampf((start_distance - nearest) / maxf(1.5, start_distance), 0.0, 1.0)
	route.exposure += approach * minf(route.seconds, context.utility_horizon_seconds)
	return route

func cover_points() -> Array:
	if _preparing_cover_points and _prepared_cover_points_ready:
		return _prepared_cover_points.duplicate()
	var threat: Vector3 = context._known_reload_threat()
	var result: Array = []
	if not threat.is_finite() or context.noise_search_origin.is_finite():
		return result
	for region in regions():
		for candidate in region.get_candidates(context.actor.get_posture_eye_position(false, threat), context.actor.global_position):
			result.append({"hide": candidate.hide, "body": region, "crouch": candidate.get("crouch", false), "stand": candidate.get("stand", Vector3.INF)})
	if _preparing_cover_points:
		_prepared_cover_points = result
		_prepared_cover_points_ready = true
		return result.duplicate()
	return result

func assess_cover_point(destination: Dictionary) -> Dictionary:
	if not cover_valid(destination):
		return {}
	var threat: Vector3 = context._known_reload_threat()
	var selection = context.cover_selection
	if selection.require_assigned_cover and selection._cover_quality(destination.hide, context.actor.get_posture_eye_position(false, threat), destination.body, destination.get("crouch", false)) < selection.minimum_cover_quality:
		return {}
	var path: PackedVector3Array = context.routes.planning_path(context.actor.global_position, destination.hide)
	var route := assess_cover_route(path, threat, float(context.setting(&"cover", &"run_speed_multiplier", 2.0)), _reload_seconds(context))
	var horizon: float = context.utility_horizon_seconds
	var exposure: float = route.exposure + context._reload_exposure(destination.hide, threat, -1.0, destination.get("crouch", false)) * maxf(0.0, horizon - route.seconds)
	var current: Dictionary = destination.duplicate()
	current.path = path
	return {"destination": current, "cost": score(horizon, exposure, horizon if not context.sees_player else maxf(0.0, horizon - route.seconds))}


func _store_candidate(cache: Array, destination: Dictionary, cost: float, assessment: Dictionary = {}) -> void:
	var point: Vector3 = destination.get("hide", destination.get("position", Vector3.INF))
	for index in range(cache.size() - 1, -1, -1):
		var previous: Dictionary = cache[index].destination
		if previous.get("body") == destination.get("body") and previous.get("hide", previous.get("position", Vector3.INF)).is_equal_approx(point):
			cache.remove_at(index)
	cache.append({"destination": destination, "cost": cost, "assessment": assessment, "time": Time.get_ticks_msec()})
	cache.sort_custom(func(a: Dictionary, b: Dictionary): return a.cost < b.cost)
	if cache.size() > CACHED_DESTINATIONS:
		cache.resize(CACHED_DESTINATIONS)

func _prune_cache(cache: Array) -> void:
	for index in range(cache.size() - 1, -1, -1):
		if (cache[index].destination.has("body") and not is_instance_valid(cache[index].destination.body)) or Time.get_ticks_msec() - cache[index].time > CACHE_LIFETIME_MSEC:
			cache.remove_at(index)

func _cached_destinations(cache: Array) -> Array:
	_prune_cache(cache)
	var result: Array = []
	for entry: Dictionary in cache:
		result.append(entry.destination)
	return result

## AI 的只读评估工具；不启动动作、不修改记忆或导航目标。
## 所有候选统一比较未来同一段时间的火力缺失、暴露与信息损失。

func _reload_seconds(ai) -> float:
	if not ai.actor.can_use_firearms():
		return 0.0
	if ai.actor.ammo.magazine_rounds > 0 and not ai.actor.ammo.is_reloading:
		return 0.0
	return maxf(0.1, ai.actor.weapon.reload_seconds) * (1.0 - ai.actor.ammo.reload_progress)

func _ammo_wait(ai) -> float:
	if not ai.actor.can_use_firearms():
		return ai.utility_horizon_seconds
	if ai.actor.ammo.is_reloading:
		return _reload_seconds(ai)
	return 0.0 if ai.actor.ammo.magazine_rounds > 0 else ai.utility_horizon_seconds

func _exposure(ai, point: Vector3, threat: Vector3) -> float:
	return ai._reload_exposure(point, threat) if threat.is_finite() else 0.0

func assess_route(ai, path: PackedVector3Array, threat: Vector3, multiplier: float, reload_seconds: float, evaluate_fire: bool = false, start_seconds: float = 0.0, start_position: Vector3 = Vector3.INF) -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame != _route_frame:
		_route_frame = frame
		_route_cache.clear()
	var fire_state: Array = [ai.fire.fire_reaction_elapsed, ai.fire.fire_reaction_seconds, ai.fire.fire_pause_remaining, ai.actor.shot_cooldown, ai.fire.fire_while_moving,
		ai.perception.sight_distance, ai.perception.close_awareness_radius, ai.actor.weapon, ai.actor.weapon.fire_range if ai.actor.weapon != null else 0.0, ai.actor.can_use_firearms()] if evaluate_fire else []
	var key := [path, threat, multiplier, reload_seconds, start_seconds, start_position, ai.actor.global_position, ai.actor.move_speed, ai.utility_horizon_seconds, evaluate_fire, fire_state]
	if _route_cache.has(key): return _route_cache[key]
	var speed: float = maxf(0.01, ai.actor.move_speed * maxf(0.0, multiplier))
	var walk_speed: float = minf(speed, maxf(0.01, ai.actor.move_speed))
	# 组合方案可先执行一个阶段再移动；路径前的暴露由调用者提供，仍使用共同时间窗。
	var seconds: float = maxf(0.0, start_seconds)
	var exposure: float = 0.0
	var fire_seconds: float = 0.0
	var keep_sight: bool = evaluate_fire and threat.is_finite() and ai.actor.can_use_firearms() and ai.fire.fire_while_moving
	var ready: float = maxf(ai.actor.shot_cooldown, maxf(ai.fire.fire_pause_remaining, ai.fire.fire_reaction_seconds - ai.fire.fire_reaction_elapsed)) if evaluate_fire else 0.0
	ready = maxf(ready, reload_seconds)
	var target: Vector3 = ai.actor.get_posture_eye_position(true, threat) if evaluate_fire else Vector3.ZERO
	var previous: Vector3 = start_position if start_position.is_finite() else ai.actor.global_position
	var horizon: float = ai.utility_horizon_seconds
	var actor_height: float = ai.actor.global_position.y
	var shot_offset: Vector3 = ai.actor.get_posture_muzzle_position(false, Vector3.ZERO) if evaluate_fire else Vector3.ZERO
	var sight_distance: float = maxf(ai.perception.sight_distance, ai.perception.close_awareness_radius) if evaluate_fire else 0.0
	var fire_range: float = ai.actor.weapon.fire_range if keep_sight else 0.0
	for point: Vector3 in path:
		var length: float = ai._horizontal_distance_between(previous, point)
		var samples: int = maxi(1, ceili(length / 0.5))
		for index: int in range(samples):
			var distance: float = length / samples
			var slow_distance: float = minf(distance, maxf(0.0, reload_seconds - seconds) * walk_speed)
			var duration: float = slow_distance / walk_speed + (distance - slow_distance) / speed
			var observed: float = minf(duration, maxf(0.0, horizon - seconds))
			if observed > 0.0:
				var sample: Vector3 = previous.lerp(point, (float(index) + 0.5) / samples)
				exposure += _exposure(ai, sample, threat) * observed
				if keep_sight:
					# 导航点悬在地面上方；射界必须按角色实际枪口高度检查。
					sample.y = actor_height
					var origin: Vector3 = sample + shot_offset
					keep_sight = (sample.distance_to(threat) <= sight_distance
						and ai.cover_selection.has_clear_line(origin, target))
					# 主动退入墙后即失视，不能预支之后绕出墙另一端的火力。
					if keep_sight and origin.distance_to(target) <= fire_range and ai.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
						fire_seconds += maxf(0.0, seconds + observed - maxf(seconds, ready))
			seconds += duration
		previous = point
	var result := {"seconds": seconds, "exposure": exposure, "fire_seconds": fire_seconds}
	_route_cache[key] = result
	return result


## 兼容动作执行分派；决策来自 assess_options，不在这里再次选方案。
