extends RefCounted

## 近战接敌共用的只读路径与结果估计；不持有动作实例，也不提交执行请求。
static func stopping_distance(context) -> float:
	var distance := maxf(0.1, float(context.setting(&"tactics", &"stopping_distance", 1.3)))
	var weapon: WeaponData = context.actor.weapon
	if weapon != null and weapon.melee_enabled:
		distance = minf(distance, maxf(0.1, weapon.melee_range - 0.05))
	return distance

static func contact_path(context, origin: Vector3 = Vector3.INF) -> PackedVector3Array:
	if not origin.is_finite(): origin = context.actor.global_position
	var target: Vector3 = context.last_known_position
	var path: PackedVector3Array = context.cover_selection._path_to(origin, target).duplicate()
	if path.is_empty():
		# 贴墙玩家可能在烘焙导航边界外。实际 Agent 也会靠向这个导航点，
		# 但只有停靠误差内仍能挥击、身体能站稳且不隔墙时，才认可这条接敌路线。
		var contact: Vector3 = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), target)
		var reach := stopping_distance(context)
		var height := 0.5
		if context.actor.weapon != null and context.actor.weapon.melee_enabled:
			reach = maxf(0.0, context.actor.weapon.melee_range - context.agent.target_desired_distance - 0.05)
			height = maxf(0.0, context.actor.weapon.melee_height_tolerance)
		if absf(contact.y - origin.y) <= 0.5 and absf(target.y - origin.y) <= height:
			contact.y = origin.y
			if context._horizontal_distance_between(contact, target) <= reach and context.is_position_free(contact) and context.cover_selection.has_clear_line(contact + Vector3.UP * 0.8, target + Vector3.UP * 0.8):
				path = context.cover_selection._path_to(origin, contact).duplicate()
	if path.is_empty():
		# 玩家能站在导航边缘外；用可出手的近侧落点求路，不要求站到玩家脚下。
		if context._horizontal_distance_between(origin, target) <= stopping_distance(context):
			return PackedVector3Array([origin])
		var near_target: Vector3 = target.move_toward(origin, stopping_distance(context))
		near_target.y = origin.y
		if context.cover_selection.has_clear_line(near_target + Vector3.UP * 0.8, target + Vector3.UP * 0.8):
			return context.cover_selection._path_to(origin, near_target).duplicate()
		return path
	for index in path.size(): path[index].y = origin.y
	# 只缩短最后一段，不跨过寻路拐点；避免把墙另一侧当成可出手位置。
	if path.size() >= 2:
		var previous: Vector3 = path[path.size() - 2]
		var endpoint: Vector3 = path[path.size() - 1]
		var length := previous.distance_to(endpoint)
		if length > 0.01:
			# 导航停靠点与玩家可能并不重合，不能在已有偏移上再退完整停止距离。
			var retreat := maxf(0.0, stopping_distance(context) - context._horizontal_distance_between(endpoint, target))
			path[path.size() - 1] = endpoint.move_toward(previous, minf(retreat, maxf(0.0, length - 0.05)))
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
