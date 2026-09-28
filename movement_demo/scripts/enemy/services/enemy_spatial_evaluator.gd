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

func register(action) -> void:
	for job in jobs:
		if job.channel == action.evaluation_channel():
			job.owners.append(weakref(action))
			return
	jobs.append({"owner": weakref(action), "owners": [weakref(action)], "channel": action.evaluation_channel(), "points": [], "cursor": 0, "priority": 0, "priority_cursor": 0, "completed_passes": 0, "cache": []})
	_position = Vector3.INF

func reset_evaluation() -> void:
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
	for job in jobs:
		job.owners = job.owners.filter(func(owner): return owner.get_ref() != null and owner.get_ref().is_enabled())
		if not job.owners.is_empty(): job.owner = job.owners[0]
	jobs = jobs.filter(func(job): return not job.owners.is_empty())
	var threat: Vector3 = context._known_reload_threat()
	var geometry: Array = [NavigationServer3D.map_get_iteration_id(context.agent.get_navigation_map())]
	for region in regions():
		var collision: CollisionShape3D = region.get_node("CollisionShape3D")
		geometry.append([region.get_instance_id(), collision.global_transform, collision.shape.size, region.hide_length_ratio, region.short_hide_length_ratio, region.hide_depth, region.wall_gap, region.sample_spacing, region.attack_inner_radius, region.attack_outer_radius, region.attack_sample_spacing])
	var signature := hash(geometry)
	var changed: bool = _visible != context.sees_player or signature != _geometry or not _position.is_finite() or _position.distance_to(context.actor.global_position) > 0.5 or threat != _threat and (not threat.is_finite() or not _threat.is_finite() or threat.distance_to(_threat) > 0.25) or _weapon != context.actor.weapon or _reloading != context.actor.ammo.is_reloading
	if changed:
		var initial: bool = not _position.is_finite() or signature != _geometry
		_visible = context.sees_player
		_geometry = signature
		_position = context.actor.global_position
		_threat = threat
		_weapon = context.actor.weapon
		_reloading = context.actor.ammo.is_reloading
		for job in jobs:
			job.cache.clear()
			var empty: bool = job.points.is_empty()
			job.points = job.owner.get_ref().evaluation_points()
			job.cursor %= maxi(1, job.points.size())
			if initial or empty:
				job.priority = mini(job.points.size(), job.owner.get_ref().evaluation_priority_count())
				job.priority_cursor = 0
				if job.priority > 0: job.cursor = job.priority % job.points.size()
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
			_store_candidate(job.cache, assessment.destination, assessment.cost)
		last_evaluated_count += 1
		total_evaluated_count += 1
	last_evaluation_usec = Time.get_ticks_usec() - started

func destinations(action) -> Array:
	for job in jobs:
		if job.channel == action.evaluation_channel():
			return _cached_destinations(job.cache)
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
	return context.cover_selection._center_hidden_by_cover(destination.hide, threat + Vector3.UP * 0.8, destination.body) and not context.cover_selection._path_to(context.actor.global_position, destination.hide).is_empty()

func cover_points() -> Array:
	var threat: Vector3 = context._known_reload_threat()
	var result: Array = []
	if not threat.is_finite() or context.noise_search_origin.is_finite():
		return result
	for region in regions():
		for candidate in region.get_candidates(threat + Vector3.UP * 0.8, context.actor.global_position):
			result.append({"hide": candidate.hide, "body": region})
	return result

func assess_cover_point(destination: Dictionary) -> Dictionary:
	if not cover_valid(destination):
		return {}
	var threat: Vector3 = context._known_reload_threat()
	var selection = context.cover_selection
	if selection.require_assigned_cover and selection._cover_quality(destination.hide, threat + Vector3.UP * 0.8, destination.body) < selection.minimum_cover_quality:
		return {}
	var path: PackedVector3Array = selection._path_to(context.actor.global_position, destination.hide)
	var route := assess_route(context, path, threat, float(context.setting(&"cover", &"run_speed_multiplier", 2.0)), _reload_seconds(context))
	var horizon: float = context.utility_horizon_seconds
	var exposure: float = route.exposure + _exposure(context, destination.hide, threat) * maxf(0.0, horizon - route.seconds)
	var current: Dictionary = destination.duplicate()
	current.path = path
	return {"destination": current, "cost": score(horizon, exposure, horizon if not context.sees_player else maxf(0.0, horizon - route.seconds))}


func _store_candidate(cache: Array, destination: Dictionary, cost: float) -> void:
	var point: Vector3 = destination.get("hide", destination.get("position", Vector3.INF))
	for index in range(cache.size() - 1, -1, -1):
		var previous: Dictionary = cache[index].destination
		if previous.get("body") == destination.get("body") and previous.get("hide", previous.get("position", Vector3.INF)).is_equal_approx(point):
			cache.remove_at(index)
	cache.append({"destination": destination, "cost": cost, "time": Time.get_ticks_msec()})
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

func assess_route(ai, path: PackedVector3Array, threat: Vector3, multiplier: float, reload_seconds: float, evaluate_fire: bool = false) -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame != _route_frame:
		_route_frame = frame
		_route_cache.clear()
	var key := [path, threat, multiplier, reload_seconds, ai.actor.global_position, ai.actor.move_speed, ai.utility_horizon_seconds]
	if not evaluate_fire and _route_cache.has(key): return _route_cache[key]
	var speed: float = maxf(0.01, ai.actor.move_speed * maxf(0.0, multiplier))
	var walk_speed: float = minf(speed, maxf(0.01, ai.actor.move_speed))
	var seconds: float = 0.0
	var exposure: float = 0.0
	var fire_seconds: float = 0.0
	var keep_sight: bool = evaluate_fire and threat.is_finite() and ai.actor.can_use_firearms() and ai.fire.fire_while_moving
	var ready: float = maxf(ai.actor.shot_cooldown, maxf(ai.fire.fire_pause_remaining, ai.fire.fire_reaction_seconds - ai.fire.fire_reaction_elapsed)) if evaluate_fire else 0.0
	var target := threat + Vector3.UP * 0.8
	var previous: Vector3 = ai.actor.global_position
	for point: Vector3 in path:
		var length: float = ai._horizontal_distance_between(previous, point)
		var samples: int = maxi(1, ceili(length / 0.5))
		for index: int in range(samples):
			var distance: float = length / samples
			var slow_distance: float = minf(distance, maxf(0.0, reload_seconds - seconds) * walk_speed)
			var duration: float = slow_distance / walk_speed + (distance - slow_distance) / speed
			var observed: float = minf(duration, maxf(0.0, ai.utility_horizon_seconds - seconds))
			if observed > 0.0:
				var sample: Vector3 = previous.lerp(point, (float(index) + 0.5) / samples)
				exposure += _exposure(ai, sample, threat) * observed
				if keep_sight:
					# 导航点悬在地面上方；射界必须按角色实际枪口高度检查。
					sample.y = ai.actor.global_position.y
					var origin: Vector3 = sample + ai.actor.get_shot_origin() - ai.actor.global_position
					keep_sight = (sample.distance_to(threat) <= maxf(ai.perception.sight_distance, ai.perception.close_awareness_radius)
						and ai.cover_selection.has_clear_line(origin, target))
					# 主动退入墙后即失视，不能预支之后绕出墙另一端的火力。
					if keep_sight and origin.distance_to(target) <= ai.actor.weapon.fire_range and ai.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
						fire_seconds += maxf(0.0, seconds + observed - maxf(seconds, ready))
			seconds += duration
		previous = point
	var result := {"seconds": seconds, "exposure": exposure, "fire_seconds": fire_seconds}
	if not evaluate_fire: _route_cache[key] = result
	return result


## 兼容动作执行分派；决策来自 assess_options，不在这里再次选方案。
