extends RefCounted

## 近战接敌共用的只读路径与结果估计；不持有动作实例，也不提交执行请求。
static func stopping_distance(context) -> float:
	var distance := maxf(0.1, float(context.setting(&"tactics", &"stopping_distance", 1.3)))
	var weapon: WeaponData = context.actor.weapon
	if weapon != null and weapon.melee_enabled:
		distance = minf(distance, maxf(0.1, weapon.melee_range - 0.05))
	return distance

static func contact_path(context) -> PackedVector3Array:
	var target: Vector3 = context.last_known_position
	var path: PackedVector3Array = context.cover_selection._path_to(context.actor.global_position, target).duplicate()
	if path.is_empty():
		# 玩家能站在导航边缘外；用可出手的近侧落点求路，不要求站到玩家脚下。
		if context._horizontal_distance(target) <= stopping_distance(context):
			return PackedVector3Array([context.actor.global_position])
		var near_target: Vector3 = target.move_toward(context.actor.global_position, stopping_distance(context))
		near_target.y = context.actor.global_position.y
		if context.cover_selection.has_clear_line(near_target + Vector3.UP * 0.8, target + Vector3.UP * 0.8):
			return context.cover_selection._path_to(context.actor.global_position, near_target).duplicate()
		return path
	for index in path.size(): path[index].y = context.actor.global_position.y
	# 只缩短最后一段，不跨过寻路拐点；避免把墙另一侧当成可出手位置。
	if path.size() >= 2:
		var previous: Vector3 = path[path.size() - 2]
		var endpoint: Vector3 = path[path.size() - 1]
		var length := previous.distance_to(endpoint)
		if length > 0.01:
			path[path.size() - 1] = endpoint.move_toward(previous, minf(stopping_distance(context), maxf(0.0, length - 0.05)))
	return path

static func contact_outcome(context, path: PackedVector3Array, multiplier: float = 1.0, fast_seconds: float = INF) -> Dictionary:
	var horizon: float = context.utility_horizon_seconds
	if is_finite(fast_seconds) and multiplier > 1.0:
		var speed: float = maxf(0.01, context.actor.move_speed)
		var length: float = context.cover_selection._path_length_from_path(path)
		var fast_distance := minf(length, speed * multiplier * maxf(0.0, fast_seconds))
		var seconds := fast_distance / (speed * multiplier) + (length - fast_distance) / speed
		# 用等效速度估计整段暴露，但到达时间严格包含突进结束后的普通移动。
		multiplier = length / (seconds * speed) if seconds > 0.0 else 1.0
	var route: Dictionary = context.spatial.assess_route(context, path, context.last_known_position, multiplier, 0.0)
	var weapon: WeaponData = context.actor.weapon
	var ready := horizon
	if weapon != null and weapon.melee_enabled and context.actor.can_equip_weapon(weapon):
		ready = maxf(route.seconds, context.actor.melee_cooldown) + maxf(0.0, weapon.melee_windup_seconds)
	var exposure: float = route.exposure
	if not path.is_empty():
		exposure += context._reload_exposure(path[path.size() - 1], context.last_known_position) * maxf(0.0, horizon - route.seconds)
	return {"unavailable_seconds": minf(horizon, ready), "exposed_seconds": opportunity_exposure(context, exposure), "information_loss": 0.0 if context.sees_player else minf(horizon, route.seconds)}

static func opportunity_exposure(context, exposure: float) -> float:
	# 只有已感知的短窗口折减暴露估计；不预知玩家枪械参数或精确换弹进度。
	var horizon: float = maxf(0.1, context.utility_horizon_seconds)
	return exposure * (1.0 - clampf(context.observed_reload_window() / horizon, 0.0, 1.0))
