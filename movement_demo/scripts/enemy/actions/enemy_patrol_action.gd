extends "res://scripts/enemy/actions/enemy_action.gd"

# 原巡逻算法，由AI更新。
func start() -> void:
	if not is_enabled():
		return
	# 激活期间不允许随机巡逻。正常情况下 SEARCH 结束时才会解除警戒。
	if context.is_alerted:
		return

	# 只从本竞技场的导航区域选点，避免走进连接通道或其他场地。
	for attempt in range(12):
		var destination = NavigationServer3D.region_get_random_point(
			context.navigation_region.get_rid(),
			agent.navigation_layers,
			true
		)

		if context._horizontal_distance(destination) < 2.0:
			continue

		var path = NavigationServer3D.map_get_path(
			agent.get_navigation_map(),
			actor.global_position,
			destination,
			true,
			agent.navigation_layers
		)

		if path.is_empty() or path[path.size() - 1].distance_to(destination) > 0.5:
			continue

		# 烘焙网格高于脚底；目标也需换成角色脚底高度才能正确判定抵达。
		destination.y -= agent.path_height_offset
		agent.target_position = destination
		context.state = context.State.PATROL
		return

	# 没有合适的点时稍后重试，避免每一帧重复查找。
	context.patrol_pause_timer = maxf(context.patrol_pause_seconds, 0.5)


func step(_delta: float) -> Vector3:
	if not is_enabled():
		return Vector3.ZERO
	var next_position: Vector3 = agent.get_next_path_position()
	if not agent.is_navigation_finished():
		var direction: Vector3 = next_position - actor.global_position
		direction.y = 0.0
		return direction.normalized()
	context.state = context.State.IDLE
	context.patrol_pause_timer = context.patrol_pause_seconds
	return Vector3.ZERO


func reset() -> void:
	pass


func collect_candidates(_visible: bool) -> Array[Dictionary]:
	if context._known_reload_threat().is_finite() or context.is_alerted or (context.state != context.State.PATROL and context.patrol_pause_timer > 0.0):
		return []
	var candidate := option({}, context.utility_horizon_seconds, 0.0)
	candidate.accepts_noise = true
	return [candidate]

func begin(candidate: Dictionary, visible: bool) -> bool:
	candidate.accepts_noise = true
	super.begin(candidate, visible)
	start()
	_running = context.state == context.State.PATROL
	return _running

func valid(_visible: bool) -> bool:
	return _running and not context.is_alerted and context.state == context.State.PATROL

func tick(delta: float, _visible: bool) -> Dictionary:
	var direction := step(delta)
	_running = context.state == context.State.PATROL
	return motion(direction, 1.0, direction)
